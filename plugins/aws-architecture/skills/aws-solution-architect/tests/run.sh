#!/usr/bin/env bash
#
# Red/green test for the validation gate.
#
# Satisfies the implementation plan's Week 2-3 exit criterion: validate.sh runs
# green/red against two hand-written reference architectures.
#
#   tier0-violating/  must FAIL, and must fail on the specific controls listed
#   tier0-compliant/  must satisfy every zero-downtime invariant
#
# Asserting *which* controls fail matters more than asserting that something
# failed. A validator that fails for the wrong reason still exits 1, and that
# is how a broken gate survives a passing test suite.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="${SCRIPT_DIR}/../scripts/validate.sh"
RENDER="${SCRIPT_DIR}/../scripts/render_diagram.py"
WORK="${TMPDIR:-/tmp}/zt-zd-tests"
FAILURES=0

# Extra flags for the next expect_state call; reset after each one so a flag
# cannot leak into a later assertion and quietly change what is being tested.
VALIDATE_ARGS=()

mkdir -p "${WORK}"

command -v terraform >/dev/null || { echo "SKIP: terraform not installed"; exit 0; }

check() {
  local label="$1" got="$2" want="$3"
  if [[ "${got}" == "${want}" ]]; then
    printf '   ok    %-28s %s\n' "${label}" "${got}"
  else
    printf '   FAIL  %-28s got %s, want %s\n' "${label}" "${got}" "${want}"
    FAILURES=$((FAILURES + 1))
  fi
}

# expect_state <fixture> <expected-exit> <control:state> ...
expect_state() {
  local fixture="$1" expect_exit="$2"; shift 2
  local dir="${SCRIPT_DIR}/reference-architectures/${fixture}"
  local out="${WORK}/${fixture}"

  echo "── ${fixture} ${VALIDATE_ARGS[*]:-}"
  terraform -chdir="${dir}" init -backend=false -input=false >/dev/null 2>&1
  bash "${VALIDATE}" "${dir}" --out "${out}" --tier 0 "${VALIDATE_ARGS[@]:-}" >/dev/null 2>&1
  local actual_exit=$?
  VALIDATE_ARGS=()

  if [[ "${actual_exit}" != "${expect_exit}" ]]; then
    echo "   FAIL  exit ${actual_exit}, expected ${expect_exit}"
    FAILURES=$((FAILURES + 1))
  fi

  for pair in "$@"; do
    local cid="${pair%%:*}" want="${pair##*:}"
    local got
    got=$(python3 -c "
import json,sys
r=json.load(open('${out}/validation.json'))
print(r['controls'].get('${cid}',{}).get('state','ABSENT'))
")
    if [[ "${got}" == "${want}" ]]; then
      printf '   ok    %-14s %s\n' "${cid}" "${got}"
    else
      printf '   FAIL  %-14s got %s, want %s\n' "${cid}" "${got}" "${want}"
      FAILURES=$((FAILURES + 1))
    fi
  done
}

# The violating fixture breaks one invariant per control, deliberately.
expect_state tier0-violating 1 \
  ZD-TOP-001:failed \
  ZD-TOP-004:failed \
  ZD-DAT-002:failed \
  ZD-DEG-001:failed \
  ZD-DEP-002:not_applicable

# The compliant fixture satisfies all five. Note the expected exit is still 1
# when the optional toolchain (conftest, aws CLI) is absent: unverified is not
# passed. Install conftest and configure credentials for a true exit 0.
# It states a Region explicitly, so INTAKE-REGION must be satisfied.
expect_state tier0-compliant 1 \
  ZD-TOP-001:satisfied \
  ZD-TOP-004:satisfied \
  ZD-DAT-002:satisfied \
  ZD-DEG-001:satisfied \
  ZD-DEP-002:satisfied \
  INTAKE-REGION:satisfied

# Region placeholder. Every zero-downtime invariant still passes — the fixture is
# the compliant one with the Region removed — so INTAKE-REGION is provably the
# only thing the placeholder changed. Asserting the others stay satisfied is the
# point: it proves the check is specific rather than a blanket failure.
expect_state tier0-region-placeholder 1 \
  INTAKE-REGION:skipped \
  ZD-TOP-001:satisfied \
  ZD-TOP-004:satisfied \
  ZD-DAT-002:satisfied \
  ZD-DEG-001:satisfied \
  ZD-DEP-002:satisfied

# Deferring deliberately downgrades it to non-blocking, and must not silently
# upgrade it to satisfied — the architecture is still unvalidated for any Region.
VALIDATE_ARGS=(--allow-region-placeholder)
expect_state tier0-region-placeholder 1 \
  INTAKE-REGION:recommended

# ---------------------------------------------------------------------------
# Diagram rendering
# ---------------------------------------------------------------------------
# The diagram is a deliverable artifact, so it is asserted like one. These check
# that it is *derived from the plan* — that it renders the resources the plan
# contains and reports an unspecified Region as unspecified — not merely that
# the script exits 0.
echo "── diagrams"

MMD="${WORK}/tier0-compliant/architecture.mmd"
TXT="${WORK}/tier0-compliant/architecture.txt"

check "mermaid written" "$([[ -s "${MMD}" ]] && echo yes || echo no)" yes
check "ascii written"   "$([[ -s "${TXT}" ]] && echo yes || echo no)" yes

if [[ -s "${MMD}" ]]; then
  # Unbalanced subgraph/end is the failure that makes Mermaid refuse to render
  # the whole diagram, and it is invisible in the source until something tries.
  check "subgraph/end balanced" \
    "$(python3 - "${MMD}" <<'PY'
import re, sys
body = open(sys.argv[1]).read().splitlines()
opens = sum(1 for l in body if l.strip().startswith("subgraph "))
closes = sum(1 for l in body if l.strip() == "end")
print("balanced" if opens == closes and opens > 0 else f"open={opens} close={closes}")
PY
)" balanced

  # Every edge endpoint must be a node that was actually emitted. An edge to an
  # undefined id makes Mermaid invent an empty box, which reads as a real
  # resource that does not exist.
  check "edge endpoints defined" \
    "$(python3 - "${MMD}" <<'PY'
import re, sys
body = open(sys.argv[1]).read()
defined = set(re.findall(r'^\s*(n_[0-9A-Za-z_]+)\["', body, re.M))
dangling = [
    e for line in body.splitlines()
    if "-->" in line and not line.strip().startswith("%%")
    for e in re.findall(r'(n_[0-9A-Za-z_]+)', line)
    if e not in defined
]
print("all-defined" if not dangling else f"dangling={dangling[:3]}")
PY
)" all-defined

  check "renders planned resource" \
    "$(grep -c 'aws_lb_target_group.tg' "${MMD}" | awk '{print ($1>0)?"yes":"no"}')" yes
  check "renders AZ failure domain" \
    "$(grep -c 'AZ us-east-1a' "${MMD}" | awk '{print ($1>0)?"yes":"no"}')" yes
  # Nesting reference resolved through a nested block (ASG -> launch template).
  check "nested-block edge drawn" \
    "$(grep -c 'launch_template|' "${MMD}" | awk '{print ($1>0)?"yes":"no"}')" yes
fi

if [[ -s "${TXT}" ]]; then
  check "ascii names Region" \
    "$(grep -c '^Region: us-east-1' "${TXT}" | awk '{print ($1>0)?"yes":"no"}')" yes
  check "ascii has provenance" \
    "$(grep -c 'Provenance' "${TXT}" | awk '{print ($1>0)?"yes":"no"}')" yes
fi

# Placement fidelity: count/for_each, public tier, and the distinction between a
# reference to one instance and a reference to a whole collection. See the
# fixture's own header for why these two cases must not render alike.
expect_state multi-instance 1
MI="${WORK}/multi-instance/architecture.txt"
if [[ -s "${MI}" ]]; then
  check "count index rendered" \
    "$(grep -c 'aws_subnet.public\[0\]' "${MI}" | awk '{print ($1>0)?"yes":"no"}')" yes
  check "for_each key rendered" \
    "$(grep -c 'aws_subnet.private\["a"\]' "${MI}" | awk '{print ($1>0)?"yes":"no"}')" yes
  check "public tier labelled" \
    "$(grep -c 'public  10.0.0.0/24' "${MI}" | awk '{print ($1>0)?"yes":"no"}')" yes
  # Pinned to one subnet: must sit inside that subnet, not span the collection.
  check "specific ref stays in one AZ" \
    "$(python3 - "${MI}" <<'PY'
import sys
lines = open(sys.argv[1]).read().splitlines()
for i, l in enumerate(lines):
    if "aws_instance.app" in l:
        ctx = "\n".join(lines[max(0, i - 3):i])
        print("in-subnet" if 'aws_subnet.private["a"]' in ctx else "elsewhere")
        break
else:
    print("absent")
PY
)" in-subnet
  # Collection ref: must span both AZs of the collection.
  check "collection ref spans AZs" \
    "$(grep -A1 'spans AZs eu-west-1a, eu-west-1b' "${MI}" | grep -c 'aws_autoscaling_group.asg' | awk '{print ($1>0)?"yes":"no"}')" yes
  # `each.key` / `count.index` are not missing nodes and must not be counted.
  check "no phantom unresolved refs" \
    "$(grep -c 'outside this plan' "${MI}" | awk '{print ($1==0)?"yes":"no"}')" yes
fi

# A placeholder Region must never render as a bare Region name in the diagram.
PH_TXT="${WORK}/tier0-region-placeholder/architecture.txt"
if [[ -s "${PH_TXT}" ]]; then
  check "placeholder Region labelled" \
    "$(grep -c 'REGION UNSPECIFIED' "${PH_TXT}" | awk '{print ($1>0)?"yes":"no"}')" yes
  check "placeholder not shown bare" \
    "$(grep -c '^Region: us-east-1$' "${PH_TXT}" | awk '{print ($1==0)?"yes":"no"}')" yes
fi

# Harness contract: a missing plan is an error (exit 2), not an empty diagram.
python3 "${RENDER}" "${WORK}/does-not-exist.json" >/dev/null 2>&1
check "missing plan exits 2" "$?" "2"

# ---------------------------------------------------------------------------
# Toolchain preflight
# ---------------------------------------------------------------------------
# The skill reads --json at intake to tell the user which binaries are missing
# and what each one costs them. That is a contract: if the shape changes, the
# user silently stops being told, which is worse than never having told them.
echo "── preflight"

PREFLIGHT="${SCRIPT_DIR}/../../../scripts/preflight.sh"
check "preflight present" "$([[ -f "${PREFLIGHT}" ]] && echo yes || echo no)" yes

if [[ -f "${PREFLIGHT}" ]]; then
  PF_JSON="$(bash "${PREFLIGHT}" --json 2>/dev/null)"
  check "json parses" \
    "$(printf '%s' "${PF_JSON}" | python3 -c 'import json,sys; json.load(sys.stdin); print("yes")' 2>/dev/null || echo no)" yes
  check "json has contract keys" \
    "$(printf '%s' "${PF_JSON}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
want = {"status", "present", "required_missing", "optional_missing", "kb_root", "consequence"}
print("all" if want <= set(d) else f"missing={sorted(want - set(d))}")
' 2>/dev/null || echo error)" all
  check "status is a known value" \
    "$(printf '%s' "${PF_JSON}" | python3 -c '
import json, sys
print(json.load(sys.stdin)["status"] in ("ok", "degraded", "fail"))
' 2>/dev/null)" True

  # Every missing-tool entry must carry the fix. A report the user cannot act on
  # is the failure mode this whole notification exists to avoid.
  check "missing entries carry install" \
    "$(printf '%s' "${PF_JSON}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
rows = d["required_missing"] + d["optional_missing"]
bad = [r for r in rows if not (r.get("bin") and r.get("why") and r.get("install"))]
print("complete" if not bad else f"incomplete={bad}")
' 2>/dev/null)" complete

  # Regression guard: two install hints contain a '|' of their own (command *or*
  # URL). An unbounded field split shifts every value one position left, which
  # previously produced entries whose "bin" was a sentence.
  # bash and python3 are invoked by absolute path: the PATH override is meant to
  # hide terraform and conftest from preflight, not to stop the test harness
  # from finding its own interpreter.
  STUB="${WORK}/stub-path"
  mkdir -p "${STUB}"
  BASH_BIN="$(command -v bash)"
  PY_BIN="$(command -v python3)"
  ln -sf "${PY_BIN}" "${STUB}/python3" 2>/dev/null
  check "required-missing exits 1" \
    "$(PATH="${STUB}" "${BASH_BIN}" "${PREFLIGHT}" --json >/dev/null 2>&1; echo $?)" 1
  check "install hint keeps its pipe" \
    "$(PATH="${STUB}" "${BASH_BIN}" "${PREFLIGHT}" --json 2>/dev/null | "${PY_BIN}" -c '
import json, sys
d = json.load(sys.stdin)
tf = [r for r in d["required_missing"] if r["bin"] == "terraform"]
print("intact" if tf and tf[0]["install"].startswith("brew install terraform")
      and "https://" in tf[0]["install"] else f"mangled={tf}")
' 2>/dev/null)" intact
fi

echo
if [[ ${FAILURES} -eq 0 ]]; then
  echo "PASS — all assertions met"
  exit 0
fi
echo "FAIL — ${FAILURES} assertion(s) failed"
exit 1
