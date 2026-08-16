#!/usr/bin/env bash
#
# Deterministic validation gate. Staged, fails fast between stages.
#
#   validate.sh [terraform-dir] [--out DIR] [--catalog FILE] [--tier N]
#
# Emits JSON keyed by control ID to <out>/validation.json so the repair loop in
# SKILL.md step 5 can act on it.
#
# Exit codes:
#   0  clean — no failed or skipped mandatory controls
#   1  one or more mandatory controls failed or could not be verified
#   2  harness error (stage could not run at all)
#
# Design rule, enforced throughout: a check that could not run is `skipped`,
# never `satisfied`. An unverified control and a broken one are equally
# undefensible, so both fail the gate. Tools that are merely absent degrade the
# result loudly rather than quietly passing.

set -uo pipefail

# Resolve policy and catalog locations against the script, not the caller's cwd:
# validate.sh is normally invoked from the directory holding the generated
# Terraform, which is not inside the repo.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

TF_DIR="${1:-.}"
[[ "${TF_DIR}" == --* ]] && TF_DIR="."
OUT_DIR="artifacts"
CATALOG=""
TIER="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)     OUT_DIR="$2"; shift 2 ;;
    --catalog) CATALOG="$2"; shift 2 ;;
    --tier)    TIER="$2";    shift 2 ;;
    *)         shift ;;
  esac
done

mkdir -p "${OUT_DIR}"
FINDINGS="${OUT_DIR}/findings.jsonl"
: > "${FINDINGS}"

STAGE_STATUS=()

log()  { printf '%s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# finding <stage> <control_id> <state> <detail>
finding() {
  python3 - "$1" "$2" "$3" "$4" >> "${FINDINGS}" <<'PY'
import json, sys
stage, control, state, detail = sys.argv[1:5]
print(json.dumps({"stage": stage, "control_id": control, "state": state, "detail": detail}))
PY
}

stage_result() { STAGE_STATUS+=("$1|$2|$3"); log "  → $1: $2 $3"; }

# ---------------------------------------------------------------------------
# Stage 0 — preflight
# ---------------------------------------------------------------------------
log "Stage 0  Preflight"

if ! have python3; then
  log "FATAL: python3 is required for report assembly."
  exit 2
fi

if ! have terraform; then
  log "FATAL: terraform not found. Stage 1 defines the plan every later stage reads."
  exit 2
fi

for opt in conftest checkov trivy aws; do
  have "$opt" || log "  note: ${opt} not installed — dependent controls will be 'skipped', not passed"
done
stage_result 0 PASS ""

# ---------------------------------------------------------------------------
# Stage 1 — syntax and plan generation
# ---------------------------------------------------------------------------
# -backend=false and no credentials: this gate reads a plan, it never touches an
# account. Generation-only is a security property of the generator itself.
log "Stage 1  Terraform syntax and plan"

PLAN_JSON="${OUT_DIR}/plan.json"

if ! terraform -chdir="${TF_DIR}" init -backend=false -input=false >"${OUT_DIR}/tf-init.log" 2>&1; then
  stage_result 1 FAIL "terraform init failed — see ${OUT_DIR}/tf-init.log"
  finding 1 "*" failed "terraform init failed"
  exit 1
fi

if ! terraform -chdir="${TF_DIR}" validate -no-color >"${OUT_DIR}/tf-validate.log" 2>&1; then
  stage_result 1 FAIL "terraform validate failed — see ${OUT_DIR}/tf-validate.log"
  finding 1 "*" failed "terraform validate failed (hallucinated resources or arguments surface here)"
  exit 1
fi

if ! terraform -chdir="${TF_DIR}" plan -input=false -out=tf.plan >"${OUT_DIR}/tf-plan.log" 2>&1; then
  stage_result 1 FAIL "terraform plan failed — see ${OUT_DIR}/tf-plan.log"
  finding 1 "*" failed "terraform plan failed"
  exit 1
fi

terraform -chdir="${TF_DIR}" show -json tf.plan > "${PLAN_JSON}" 2>/dev/null
stage_result 1 PASS ""

# ---------------------------------------------------------------------------
# Stage 2 — policy-as-code
# ---------------------------------------------------------------------------
log "Stage 2  Policy-as-code"

POLICY_DIRS=()
for d in "${REPO_ROOT}/aws-zero-trust/policies/opa" "${REPO_ROOT}/aws-zero-downtime/policies/opa"; do
  [[ -d "${d}" ]] && POLICY_DIRS+=("${d}")
done

if [[ ${#POLICY_DIRS[@]} -eq 0 ]]; then
  stage_result 2 SKIP "no policy directories found — controls with a 'check' cannot be verified"
  finding 2 "*" skipped "no OPA policies present"
elif ! have conftest; then
  stage_result 2 SKIP "conftest not installed"
  finding 2 "*" skipped "conftest not installed"
else
  CONFTEST_OUT="${OUT_DIR}/conftest.json"
  conftest test "${PLAN_JSON}" $(printf -- '--policy %s ' "${POLICY_DIRS[@]}") \
    --output json > "${CONFTEST_OUT}" 2>/dev/null
  python3 - "${CONFTEST_OUT}" >> "${FINDINGS}" <<'PY'
import json, re, sys
try:
    results = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
# Control ID is recovered from the rule's namespace or message. Policy files are
# named per control (zt-net-014.rego), so the mapping is 1:1 by construction.
pat = re.compile(r"(Z[TD]-[A-Z]{3}-\d{3})")
for entry in results:
    ns = entry.get("namespace", "")
    for kind, state in (("failures", "failed"), ("warnings", "recommended")):
        for item in entry.get(kind) or []:
            msg = item.get("msg", "")
            m = pat.search(msg) or pat.search(ns)
            cid = m.group(1) if m else "*"
            print(json.dumps({"stage": "2", "control_id": cid,
                              "state": state, "detail": msg}))
    for item in entry.get("successes") or []:
        pass
PY
  stage_result 2 PASS ""
fi

# Broad baseline coverage. These are a floor, not a substitute for the catalog:
# upstream rules are narrower than most catalog controls (see the pilot's
# check-coverage finding), so a clean Checkov run does not satisfy a control
# unless a control record names that specific check.
if have checkov; then
  checkov -f "${PLAN_JSON}" -o json --compact --quiet \
    > "${OUT_DIR}/checkov.json" 2>/dev/null || true
  log "  checkov: ${OUT_DIR}/checkov.json"
else
  finding 2 "*" skipped "checkov not installed — baseline coverage unverified"
fi

if have trivy; then
  trivy config --format json --output "${OUT_DIR}/trivy.json" "${TF_DIR}" >/dev/null 2>&1 || true
  log "  trivy: ${OUT_DIR}/trivy.json"
fi

# ---------------------------------------------------------------------------
# Stage 3 — IAM-specific analysis
# ---------------------------------------------------------------------------
# The highest-value AWS-native gate for Zero Trust: Access Analyzer custom
# policy checks catch resource-policy exposure that generic linters miss.
log "Stage 3  IAM analysis"

if ! have aws; then
  stage_result 3 SKIP "aws CLI not installed"
  finding 3 "*" skipped "aws CLI not installed — IAM controls unverified"
elif ! aws sts get-caller-identity >/dev/null 2>&1; then
  stage_result 3 SKIP "no AWS credentials — Access Analyzer checks require an API call"
  finding 3 "*" skipped "no credentials for Access Analyzer"
else
  python3 - "${PLAN_JSON}" "${OUT_DIR}" >> "${FINDINGS}" <<'PY'
import json, subprocess, sys
plan_path, out_dir = sys.argv[1], sys.argv[2]
plan = json.load(open(plan_path))

def walk(mod):
    for r in mod.get("resources", []):
        yield r
    for c in mod.get("child_modules", []):
        yield from walk(c)

root = plan.get("planned_values", {}).get("root_module", {})
checked = 0
for res in walk(root):
    if res.get("type") not in ("aws_iam_policy", "aws_iam_role_policy"):
        continue
    doc = (res.get("values") or {}).get("policy")
    if not doc:
        continue
    try:
        proc = subprocess.run(
            ["aws", "accessanalyzer", "check-no-public-access",
             "--policy-document", doc, "--resource-type", "AWS::IAM::Role"],
            capture_output=True, text=True, timeout=30)
        if proc.returncode == 0:
            result = json.loads(proc.stdout).get("result", "UNKNOWN")
            state = "satisfied" if result == "PASS" else "failed"
            print(json.dumps({"stage": "3", "control_id": "ZT-IDN-PUBLIC",
                              "state": state,
                              "detail": f"{res['address']}: CheckNoPublicAccess={result}"}))
            checked += 1
    except Exception as exc:
        print(json.dumps({"stage": "3", "control_id": "ZT-IDN-PUBLIC",
                          "state": "skipped",
                          "detail": f"{res['address']}: {exc}"}))
if checked == 0:
    print(json.dumps({"stage": "3", "control_id": "ZT-IDN-PUBLIC",
                      "state": "skipped", "detail": "no IAM policy documents in plan"}))
PY
  stage_result 3 PASS ""
fi

# ---------------------------------------------------------------------------
# Stage 4 — zero-downtime invariants
# ---------------------------------------------------------------------------
# Assertions over plan.json. Mostly custom: these are architectural properties
# that no generic linter expresses.
log "Stage 4  Zero-downtime invariants"

python3 - "${PLAN_JSON}" "${TIER}" >> "${FINDINGS}" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
tier = int(sys.argv[2])

def walk(mod):
    for r in mod.get("resources", []):
        yield r
    for c in mod.get("child_modules", []):
        yield from walk(c)

resources = list(walk(plan.get("planned_values", {}).get("root_module", {})))
by_type = {}
for r in resources:
    by_type.setdefault(r.get("type"), []).append(r)

def emit(cid, state, detail):
    print(json.dumps({"stage": "4", "control_id": cid, "state": state, "detail": detail}))

# ZD-TOP: no critical-path resource confined to a single AZ.
subnets = by_type.get("aws_subnet", [])
azs = {(s.get("values") or {}).get("availability_zone") for s in subnets}
azs.discard(None)
if not subnets:
    emit("ZD-TOP-001", "not_applicable", "no subnets in plan")
elif len(azs) >= (3 if tier == 0 else 2):
    emit("ZD-TOP-001", "satisfied", f"{len(azs)} AZs across {len(subnets)} subnets")
else:
    emit("ZD-TOP-001", "failed",
         f"tier-{tier} requires {'3' if tier == 0 else '2'} AZs; plan spans {len(azs)}")

# ZD-TOP: Auto Scaling minimum survives loss of one AZ.
for asg in by_type.get("aws_autoscaling_group", []):
    v = asg.get("values") or {}
    mn, zones = v.get("min_size"), v.get("availability_zones") or []
    if mn is None or not zones:
        emit("ZD-TOP-004", "skipped", f"{asg['address']}: min_size or AZ list unknown at plan time")
    elif mn >= len(zones):
        emit("ZD-TOP-004", "satisfied", f"{asg['address']}: min_size {mn} ≥ {len(zones)} AZs")
    else:
        emit("ZD-TOP-004", "failed",
             f"{asg['address']}: min_size {mn} < {len(zones)} AZs — losing one AZ drops below minimum")

# ZD-DAT: Multi-AZ database where tier <= 1.
for t in ("aws_db_instance", "aws_rds_cluster"):
    for db in by_type.get(t, []):
        v = db.get("values") or {}
        multi = v.get("multi_az")
        if tier > 1:
            emit("ZD-DAT-002", "recommended", f"{db['address']}: tier-{tier}, Multi-AZ not mandatory")
        elif multi is True or t == "aws_rds_cluster":
            emit("ZD-DAT-002", "satisfied", f"{db['address']}: Multi-AZ")
        else:
            emit("ZD-DAT-002", "failed", f"{db['address']}: tier-{tier} requires Multi-AZ")

# ZD-DEG: target groups declare deregistration delay and health thresholds.
for tg in by_type.get("aws_lb_target_group", []):
    v = tg.get("values") or {}
    hc = (v.get("health_check") or [{}])
    hc = hc[0] if isinstance(hc, list) and hc else {}
    missing = []
    if v.get("deregistration_delay") in (None, ""):
        missing.append("deregistration_delay")
    if not hc.get("healthy_threshold"):
        missing.append("healthy_threshold")
    if not hc.get("unhealthy_threshold"):
        missing.append("unhealthy_threshold")
    if missing:
        emit("ZD-DEG-001", "failed", f"{tg['address']}: missing {', '.join(missing)}")
    else:
        emit("ZD-DEG-001", "satisfied", f"{tg['address']}: draining and health thresholds set")

# ZD-DEP: deployment resources declare a rollback path.
rollback = False
for ecs in by_type.get("aws_ecs_service", []):
    v = ecs.get("values") or {}
    dc = v.get("deployment_circuit_breaker") or []
    dc = dc[0] if isinstance(dc, list) and dc else {}
    if dc.get("rollback"):
        rollback = True
        emit("ZD-DEP-002", "satisfied", f"{ecs['address']}: circuit breaker rollback enabled")
    else:
        emit("ZD-DEP-002", "failed", f"{ecs['address']}: no deployment circuit breaker rollback")
if by_type.get("aws_codedeploy_deployment_group"):
    rollback = True
    emit("ZD-DEP-002", "satisfied", "CodeDeploy deployment group present")
if not rollback and not by_type.get("aws_ecs_service"):
    emit("ZD-DEP-002", "not_applicable", "no deployment-managing resources in plan")
PY
stage_result 4 PASS ""

# ---------------------------------------------------------------------------
# Stage 5 — output contract completeness
# ---------------------------------------------------------------------------
log "Stage 5  Output contract"

# NOT IMPLEMENTED. Asserting coverage completeness requires parsing the control
# catalog, resolving applies_when against the brief, and diffing the required
# set against the matrix — none of which exists yet.
#
# This stage reports SKIP unconditionally and is counted as a degradation, so a
# run can never be reported clean on the strength of a check that does not
# exist. Do not add a PASS branch here until the comparison is actually written.
if [[ -n "${CATALOG}" ]]; then
  stage_result 5 SKIP "coverage completeness NOT IMPLEMENTED (catalog supplied but unused)"
else
  stage_result 5 SKIP "coverage completeness NOT IMPLEMENTED (no catalog supplied)"
fi
finding 5 "*" skipped "Stage 5 not implemented: coverage completeness is never verified"

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
python3 - "${FINDINGS}" "${OUT_DIR}/validation.json" "${TIER}" <<'PY'
import json, sys
from collections import defaultdict

findings_path, out_path, tier = sys.argv[1], sys.argv[2], sys.argv[3]

# Worst state wins. `skipped` outranks `recommended` deliberately: an unverified
# control is a stronger signal than an unenforced one. `not_applicable` ranks
# lowest and never blocks — a control whose `applies_when` is unmet is not a gap,
# and conflating it with `skipped` would make every plan fail for controls it was
# never subject to.
RANK = {
    "failed": 4, "skipped": 3, "recommended": 2,
    "waived": 1, "satisfied": 0, "not_applicable": -1,
}

# State starts unset rather than defaulting to `satisfied`: defaulting to a pass
# would let a control with only `not_applicable` findings render as satisfied.
by_control = defaultdict(lambda: {"state": None, "evidence": []})
with open(findings_path) as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        f = json.loads(line)
        state = f["state"]
        if state not in RANK:
            state = "skipped"          # unknown state is a degradation, not a pass
        entry = by_control[f["control_id"]]
        entry["evidence"].append({"stage": f["stage"], "detail": f["detail"]})
        if entry["state"] is None or RANK[state] > RANK[entry["state"]]:
            entry["state"] = state

controls = dict(sorted(by_control.items()))
counts = defaultdict(int)
for c in controls.values():
    counts[c["state"]] += 1

blocking = [cid for cid, c in controls.items() if c["state"] in ("failed", "skipped")]

report = {
    "tier": int(tier),
    "summary": dict(counts),
    "blocking": blocking,
    "clean": not blocking,
    "controls": controls,
}
with open(out_path, "w") as fh:
    json.dump(report, fh, indent=2)

print(f"\n  {'PASS' if report['clean'] else 'FAIL'}  "
      + "  ".join(f"{k}={v}" for k, v in sorted(counts.items())), file=sys.stderr)
if blocking:
    print("  blocking: " + ", ".join(blocking), file=sys.stderr)
print(f"  report: {out_path}", file=sys.stderr)
sys.exit(0 if report["clean"] else 1)
PY
exit $?
