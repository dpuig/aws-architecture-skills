#!/usr/bin/env bash
#
# Asserts every deny rule in policies/opa/ fires against the violating fixture,
# and that the tier-aware Stage 4 invariants report correctly.
#
# A policy that compiles but never fires is worse than no policy: it reports
# clean and is counted as coverage. Two ZD rules shipped in exactly that state
# before this suite caught them — one depended on a value that is unknown at
# plan time, the other on Rego treating JSON null as truthy.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
POLICIES="${SCRIPT_DIR}/../policies/opa"
FIXTURE="${SCRIPT_DIR}/fixtures/violating"
VALIDATE="${SCRIPT_DIR}/../../aws-solution-architect/scripts/validate.sh"
WORK="${TMPDIR:-/tmp}/zd-policy-tests"
FAILURES=0

mkdir -p "${WORK}"

command -v terraform >/dev/null || { echo "SKIP: terraform not installed"; exit 0; }
command -v conftest  >/dev/null || { echo "SKIP: conftest not installed";  exit 0; }

terraform -chdir="${FIXTURE}" init -backend=false -input=false >/dev/null 2>&1
terraform -chdir="${FIXTURE}" plan -input=false -out=tf.plan   >/dev/null 2>&1
terraform -chdir="${FIXTURE}" show -json tf.plan > "${WORK}/plan.json" 2>/dev/null

echo "── policies compile"
if conftest verify --policy "${POLICIES}" >/dev/null 2>&1; then
  echo "   ok    all policies parse"
else
  echo "   FAIL  policy compilation error"
  FAILURES=$((FAILURES + 1))
fi

echo "── Stage 2 policies fire"
OUT=$(conftest test "${WORK}/plan.json" --policy "${POLICIES}" 2>&1)
for cid in ZD-TOP-011 ZD-DEP-003 ZD-DAT-003 ZD-DAT-004 ZD-DEG-009; do
  if grep -q "${cid}:" <<<"${OUT}"; then
    printf '   ok    %-14s fired\n' "${cid}"
  else
    printf '   FAIL  %-14s did not fire\n' "${cid}"
    FAILURES=$((FAILURES + 1))
  fi
done

# ZD-TOP-011 carries three separate rules; a regression in any one of them is
# invisible if only the control ID is asserted.
echo "── ZD-TOP-011 sub-rules"
for pattern in "cross-zone" "health_check_type" "health_check_id"; do
  if grep -q "${pattern}" <<<"${OUT}"; then
    printf '   ok    %-18s rule fired\n' "${pattern}"
  else
    printf '   FAIL  %-18s rule did not fire\n' "${pattern}"
    FAILURES=$((FAILURES + 1))
  fi
done

echo "── Stage 4 tier-aware invariants"
bash "${VALIDATE}" "${FIXTURE}" --out "${WORK}/out" --tier 0 >/dev/null 2>&1
check_state() {
  local cid="$1" want="$2" got
  got=$(python3 -c "
import json
r=json.load(open('${WORK}/out/validation.json'))
print(r['controls'].get('${cid}',{}).get('state','ABSENT'))
")
  if [[ "${got}" == "${want}" ]]; then
    printf '   ok    %-14s %s\n' "${cid}" "${got}"
  else
    printf '   FAIL  %-14s got %s, want %s\n' "${cid}" "${got}" "${want}"
    FAILURES=$((FAILURES + 1))
  fi
}
check_state ZD-TOP-001 failed        # 1 AZ, tier 0 requires 3
check_state ZD-TOP-004 satisfied     # min_size 3 across 3 AZs
check_state ZD-DAT-002 failed        # no multi_az
check_state ZD-DEG-001 satisfied     # dereg delay + thresholds set
check_state ZD-DEP-002 not_applicable

echo
if [[ ${FAILURES} -eq 0 ]]; then
  echo "PASS — all assertions met"
  exit 0
fi
echo "FAIL — ${FAILURES} assertion(s) failed"
exit 1
