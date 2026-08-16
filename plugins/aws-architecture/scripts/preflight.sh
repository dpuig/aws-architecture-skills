#!/usr/bin/env bash
#
# Toolchain preflight. Run once after installing the plugin.
#
#   ./scripts/preflight.sh
#
# Why this exists: the validator treats an unverified control exactly like a
# failed one, so an incomplete toolchain makes every run report FAIL — including
# runs on correct architectures. That trains people to ignore the gate, which
# defeats it entirely. Better to fail loudly once, here, than quietly forever.

set -uo pipefail

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; OFF=$'\033[0m'
MISSING_REQUIRED=0
MISSING_OPTIONAL=0

check() {
  local bin="$1" kind="$2" why="$3" install="$4"
  if command -v "$bin" >/dev/null 2>&1; then
    printf '  %s✓%s %-11s %s\n' "$GRN" "$OFF" "$bin" "$(($bin --version 2>/dev/null || echo '') | head -1)"
  elif [[ "$kind" == required ]]; then
    printf '  %s✗%s %-11s REQUIRED — %s\n      install: %s\n' "$RED" "$OFF" "$bin" "$why" "$install"
    MISSING_REQUIRED=$((MISSING_REQUIRED + 1))
  else
    printf '  %s—%s %-11s optional — %s\n      install: %s\n' "$YEL" "$OFF" "$bin" "$why" "$install"
    MISSING_OPTIONAL=$((MISSING_OPTIONAL + 1))
  fi
}

echo "AWS architecture plugin — toolchain preflight"
echo

check python3   required "report assembly and retrieval (kb_search.py)" "system package manager"
check terraform required "validator Stage 1: syntax, plan, and plan.json"  "brew install terraform  |  https://developer.hashicorp.com/terraform/install"
check conftest  required "validator Stage 2: the 17 OPA policies"          "brew install conftest   |  https://www.conftest.dev/install/"
check checkov   optional "validator Stage 2: broad baseline coverage"      "pip install checkov"
check trivy     optional "validator Stage 2: misconfiguration scanning"    "brew install trivy"
check aws       optional "validator Stage 3: IAM Access Analyzer checks"   "brew install awscli"

echo
echo "Retrieval corpus:"
if [[ -n "${KB_ROOT:-}" ]]; then
  if [[ -d "${KB_ROOT}" ]]; then
    printf '  %s✓%s KB_ROOT=%s\n' "$GRN" "$OFF" "${KB_ROOT}"
  else
    printf '  %s✗%s KB_ROOT is set but does not exist: %s\n' "$RED" "$OFF" "${KB_ROOT}"
    MISSING_REQUIRED=$((MISSING_REQUIRED + 1))
  fi
else
  printf '  %s—%s KB_ROOT unset. Retrieval is unavailable, so every claim not\n' "$YEL" "$OFF"
  printf '      covered by a catalog control will be marked UNGROUNDED.\n'
  printf '      This is expected on a fresh install — the curated corpus is\n'
  printf '      yours and is deliberately not shipped with the plugin.\n'
fi

echo
if [[ ${MISSING_REQUIRED} -gt 0 ]]; then
  printf '%sFAIL%s  %d required tool(s) missing. The validator cannot run.\n' "$RED" "$OFF" "${MISSING_REQUIRED}"
  exit 1
fi
if [[ ${MISSING_OPTIONAL} -gt 0 ]]; then
  printf '%sOK (degraded)%s  %d optional tool(s) missing.\n' "$YEL" "$OFF" "${MISSING_OPTIONAL}"
  printf 'Controls those stages would verify are reported "skipped", never "satisfied",\n'
  printf 'so the validator will not return 0 until they are installed. That is by design.\n'
  exit 0
fi
printf '%sOK%s  full toolchain present.\n' "$GRN" "$OFF"
