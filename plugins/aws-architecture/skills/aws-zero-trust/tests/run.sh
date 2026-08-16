#!/usr/bin/env bash
#
# Asserts every deny rule in policies/opa/ fires against the violating fixture.
#
# A policy that compiles but never fires is worse than no policy: it reports
# clean and is counted as coverage. This suite exists to catch that.
#
# ZT-DAT-002 and ZT-WLD-005 need a database, which the ZT fixture does not have.
# They are exercised by aws-solution-architect/tests (tier0-violating) instead,
# and asserted here against that fixture's plan.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
POLICIES="${SCRIPT_DIR}/../policies/opa"
ZT_FIXTURE="${SCRIPT_DIR}/fixtures/violating"
ZD_FIXTURE="${SCRIPT_DIR}/../../aws-solution-architect/tests/reference-architectures/tier0-violating"
WORK="${TMPDIR:-/tmp}/zt-policy-tests"
FAILURES=0

mkdir -p "${WORK}"

command -v terraform >/dev/null || { echo "SKIP: terraform not installed"; exit 0; }
command -v conftest  >/dev/null || { echo "SKIP: conftest not installed";  exit 0; }

plan_json() {
  local dir="$1" out="$2"
  terraform -chdir="${dir}" init -backend=false -input=false >/dev/null 2>&1
  terraform -chdir="${dir}" plan -input=false -out=tf.plan   >/dev/null 2>&1
  terraform -chdir="${dir}" show -json tf.plan > "${out}" 2>/dev/null
}

# assert_fires <plan.json> <control-id>...
assert_fires() {
  local plan="$1"; shift
  local output
  output=$(conftest test "${plan}" --policy "${POLICIES}" 2>&1)
  for cid in "$@"; do
    if grep -q "${cid}" <<<"${output}"; then
      printf '   ok    %-14s fired\n' "${cid}"
    else
      printf '   FAIL  %-14s did not fire\n' "${cid}"
      FAILURES=$((FAILURES + 1))
    fi
  done
}

echo "── policies compile"
if conftest verify --policy "${POLICIES}" >/dev/null 2>&1; then
  echo "   ok    all policies parse"
else
  echo "   FAIL  policy compilation error"
  FAILURES=$((FAILURES + 1))
fi

echo "── ZT violating fixture"
touch "${ZT_FIXTURE}/placeholder.zip"
plan_json "${ZT_FIXTURE}" "${WORK}/zt.json"
assert_fires "${WORK}/zt.json" \
  ZT-NET-003 ZT-NET-014 ZT-NET-015 ZT-NET-016 \
  ZT-IDN-005 ZT-IDN-006 ZT-WLD-001 ZT-DAT-005 ZT-DAT-006 ZT-TEL-001

echo "── database-bearing fixture (ZT-DAT-002, ZT-WLD-005)"
plan_json "${ZD_FIXTURE}" "${WORK}/zd.json"
assert_fires "${WORK}/zd.json" ZT-DAT-002 ZT-WLD-005

echo
if [[ ${FAILURES} -eq 0 ]]; then
  echo "PASS — all 12 policies fire"
  exit 0
fi
echo "FAIL — ${FAILURES} assertion(s) failed"
exit 1
