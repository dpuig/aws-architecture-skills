#!/usr/bin/env bash
#
# Toolchain preflight. Run once after installing the plugin.
#
#   ./scripts/preflight.sh [--json]
#
# Why this exists: the validator treats an unverified control exactly like a
# failed one, so an incomplete toolchain makes every run report FAIL — including
# runs on correct architectures. That trains people to ignore the gate, which
# defeats it entirely. Better to fail loudly once, here, than quietly forever.
#
# --json emits the same findings as a machine-readable object so the skill can
# tell the user what is missing *at intake*, when installing a tool is cheap,
# rather than at validation time when the design work is already done.
#
# Exit codes:
#   0  full toolchain, or optional tools missing (degraded but usable)
#   1  a required tool is missing — the validator cannot run at all

set -uo pipefail

JSON=0
[[ "${1:-}" == "--json" ]] && JSON=1

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; OFF=$'\033[0m'

# bin | kind | why it matters | how to install
TOOLS=(
  "python3|required|report assembly and retrieval (kb_search.py)|system package manager"
  "terraform|required|validator Stage 1: syntax, plan, and plan.json|brew install terraform  |  https://developer.hashicorp.com/terraform/install"
  "conftest|required|validator Stage 2: the 17 OPA policies|brew install conftest   |  https://www.conftest.dev/install/"
  "checkov|optional|validator Stage 2: broad baseline coverage|pip install checkov"
  "trivy|optional|validator Stage 2: misconfiguration scanning|brew install trivy"
  "aws|optional|validator Stage 3: IAM Access Analyzer checks|brew install awscli"
)

PRESENT=(); MISSING_REQ=(); MISSING_OPT=()

for row in "${TOOLS[@]}"; do
  IFS='|' read -r bin kind why install <<<"${row}"
  # The install hints themselves contain '|', so recover the remainder.
  install="${row#*|*|*|}"
  if command -v "${bin}" >/dev/null 2>&1; then
    PRESENT+=("${bin}")
  elif [[ "${kind}" == required ]]; then
    MISSING_REQ+=("${bin}|${why}|${install}")
  else
    MISSING_OPT+=("${bin}|${why}|${install}")
  fi
done

KB_STATE="unset"
if [[ -n "${KB_ROOT:-}" ]]; then
  if [[ -d "${KB_ROOT}" ]]; then KB_STATE="ok"; else KB_STATE="invalid"; fi
fi

STATUS="ok"
[[ ${#MISSING_OPT[@]} -gt 0 ]] && STATUS="degraded"
[[ ${#MISSING_REQ[@]} -gt 0 || "${KB_STATE}" == "invalid" ]] && STATUS="fail"

# ---------------------------------------------------------------------------
# JSON
# ---------------------------------------------------------------------------
if [[ ${JSON} -eq 1 ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    # python3 is itself a required tool, so it can be the thing that is missing.
    # Emit valid JSON by hand rather than failing to report the failure.
    printf '{"status":"fail","required_missing":[{"bin":"python3","why":"report assembly and retrieval (kb_search.py)","install":"system package manager"}],"optional_missing":[],"present":[],"kb_root":"%s","consequence":"python3 is required; preflight cannot introspect further without it."}\n' "${KB_STATE}"
    exit 1
  fi
  # Entries are joined with newlines, not spaces: every field contains spaces,
  # so "${ARR[*]}" would fuse adjacent entries into one unparseable run.
  join_lines() { [[ $# -eq 0 ]] || printf '%s\n' "$@"; }
  python3 - "${STATUS}" "${KB_STATE}" "${PRESENT[*]:-}" \
    "$(join_lines "${MISSING_REQ[@]:-}")" "$(join_lines "${MISSING_OPT[@]:-}")" <<'PY'
import json, sys
status, kb, present, req, opt = sys.argv[1:6]

def rows(blob):
    """Parse `bin|why|install` lines.

    Split into exactly three fields: some install hints contain a '|' of their
    own (a package manager command *or* a download URL), and an unbounded split
    would shift every field one position left.
    """
    out = []
    for line in blob.splitlines():
        if not line.strip():
            continue
        parts = line.split("|", 2)
        if len(parts) < 3:
            continue
        out.append({"bin": parts[0].strip(),
                    "why": parts[1].strip(),
                    "install": parts[2].strip()})
    return out

consequence = {
    "ok": "Full toolchain present. Every control with a check can be verified.",
    "degraded": ("Controls those stages would verify report 'skipped', never "
                 "'satisfied', and a skipped control blocks the gate exactly as a "
                 "failure does. The validator will not return 0 until they are "
                 "installed."),
    "fail": "A required tool is missing. The validator cannot run at all.",
}[status]

print(json.dumps({
    "status": status,
    "present": present.split(),
    "required_missing": rows(req),
    "optional_missing": rows(opt),
    "kb_root": kb,
    "consequence": consequence,
}, indent=2))
PY
  [[ "${STATUS}" == "fail" ]] && exit 1
  exit 0
fi

# ---------------------------------------------------------------------------
# Human
# ---------------------------------------------------------------------------
echo "AWS architecture plugin — toolchain preflight"
echo

for row in "${TOOLS[@]}"; do
  IFS='|' read -r bin kind why _ <<<"${row}"
  install="${row#*|*|*|}"
  if command -v "${bin}" >/dev/null 2>&1; then
    printf '  %s✓%s %-11s %s\n' "$GRN" "$OFF" "${bin}" \
      "$( ("${bin}" --version 2>/dev/null || echo '') | head -1 )"
  elif [[ "${kind}" == required ]]; then
    printf '  %s✗%s %-11s REQUIRED — %s\n      install: %s\n' "$RED" "$OFF" "${bin}" "${why}" "${install}"
  else
    printf '  %s—%s %-11s optional — %s\n      install: %s\n' "$YEL" "$OFF" "${bin}" "${why}" "${install}"
  fi
done

echo
echo "Retrieval corpus:"
case "${KB_STATE}" in
  ok)      printf '  %s✓%s KB_ROOT=%s\n' "$GRN" "$OFF" "${KB_ROOT}" ;;
  invalid) printf '  %s✗%s KB_ROOT is set but does not exist: %s\n' "$RED" "$OFF" "${KB_ROOT}" ;;
  unset)
    printf '  %s—%s KB_ROOT unset. Retrieval is unavailable, so every claim not\n' "$YEL" "$OFF"
    printf '      covered by a catalog control will be marked UNGROUNDED.\n'
    printf '      This is expected on a fresh install — the curated corpus is\n'
    printf '      yours and is deliberately not shipped with the plugin.\n' ;;
esac

echo
if [[ "${STATUS}" == "fail" ]]; then
  printf '%sFAIL%s  %d required tool(s) missing. The validator cannot run.\n' \
    "$RED" "$OFF" "${#MISSING_REQ[@]}"
  exit 1
fi
if [[ "${STATUS}" == "degraded" ]]; then
  printf '%sOK (degraded)%s  %d optional tool(s) missing.\n' "$YEL" "$OFF" "${#MISSING_OPT[@]}"
  printf 'Controls those stages would verify are reported "skipped", never "satisfied",\n'
  printf 'so the validator will not return 0 until they are installed. That is by design.\n'
  exit 0
fi
printf '%sOK%s  full toolchain present.\n' "$GRN" "$OFF"
