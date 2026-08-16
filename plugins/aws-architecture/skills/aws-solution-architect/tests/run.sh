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
WORK="${TMPDIR:-/tmp}/zt-zd-tests"
FAILURES=0

mkdir -p "${WORK}"

command -v terraform >/dev/null || { echo "SKIP: terraform not installed"; exit 0; }

# expect_state <fixture> <expected-exit> <control:state> ...
expect_state() {
  local fixture="$1" expect_exit="$2"; shift 2
  local dir="${SCRIPT_DIR}/reference-architectures/${fixture}"
  local out="${WORK}/${fixture}"

  echo "── ${fixture}"
  terraform -chdir="${dir}" init -backend=false -input=false >/dev/null 2>&1
  bash "${VALIDATE}" "${dir}" --out "${out}" --tier 0 >/dev/null 2>&1
  local actual_exit=$?

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
expect_state tier0-compliant 1 \
  ZD-TOP-001:satisfied \
  ZD-TOP-004:satisfied \
  ZD-DAT-002:satisfied \
  ZD-DEG-001:satisfied \
  ZD-DEP-002:satisfied

echo
if [[ ${FAILURES} -eq 0 ]]; then
  echo "PASS — all assertions met"
  exit 0
fi
echo "FAIL — ${FAILURES} assertion(s) failed"
exit 1
