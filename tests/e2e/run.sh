#!/usr/bin/env bash
# tests/e2e/run.sh — the single documented entry point for Loom's e2e suites.
# Contract: specs/001-e2e-test-system/contracts/cli.md
#
#   run.sh [--suite S ...] [--full] [--harness H ...] [--variant V ...]
#          [--keep | --keep-on-failure | --clean]
#          [--timeout SECONDS] [--ceiling-usd N] [--trials N]
#          [--pinned | --advisory] [--no-trust-seed]
#          [--results-dir DIR] [--bootstrap] [--list] [--help]
#
# Exit status: 0 every selected mandatory check succeeded · 1 a check failed ·
#   2 usage error · 3 mandatory check blocked/skipped · 4 oracle integrity
#   failure · 5 prerequisite failure before any suite ran.
set -euo pipefail

E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${E2E_ROOT}/../.." && pwd)"
SPECS_DIR="${REPO_ROOT}/specs/001-e2e-test-system"

ALL_SUITES="offline mutation live conformance intent"
ALL_HARNESSES="claude codex opencode devin"

SUITES=(); HARNESSES=(); VARIANTS=()
FULL=0; KEEP_MODE="${LOOM_E2E_KEEP:-keep-on-failure}"
TIMEOUT=""; CEILING_USD=""; TRIALS=""
PINNED=""; NO_TRUST_SEED=0
RESULTS_DIR="${E2E_ROOT}/results"
DO_BOOTSTRAP=0; DO_LIST=0

usage() { sed -n '1,60p' "${E2E_ROOT}/README.md" >/dev/null 2>&1; cat <<'USAGE'
usage: tests/e2e/run.sh [--suite S ...] [--full] [--harness H ...] [--variant V ...]
       [--keep | --keep-on-failure | --clean]
       [--timeout SECONDS] [--ceiling-usd N] [--trials N]
       [--pinned | --advisory] [--no-trust-seed]
       [--results-dir DIR] [--bootstrap] [--list] [--help]

  --suite S        one of offline, mutation, live, conformance, intent (repeatable; default: offline)
  --full           every suite, every required harness; every mandatory check must succeed
  --harness H      claude, codex, opencode, devin (repeatable; default: all available)
  --variant V      fixture variant (repeatable; default: base); --variant all runs every declared variant
  --keep | --keep-on-failure | --clean
                   workspace retention (default: --keep-on-failure; $LOOM_E2E_KEEP also honoured)
  --timeout SECONDS     optional per-scenario wall-clock ceiling (unset = unbounded)
  --ceiling-usd N       optional model-spend ceiling per run (unset = unbounded)
  --trials N            override model-driven trial count
  --pinned | --advisory pinned blocks a harness layer on version mismatch (CI default);
                   advisory runs and labels outcomes unpinned (local default)
  --no-trust-seed  skip trust seeding (untrusted-canary negative check)
  --results-dir DIR     where the run directory is created (default: tests/e2e/results)
  --bootstrap      create the local virtualenv with the pinned jsonschema, then exit
  --list           print suites, variants, harnesses and check ids, then exit
  --help           print this help and exit

exit status: 0 every selected mandatory check succeeded · 1 a check failed · 2 usage error ·
  3 mandatory check blocked or skipped · 4 oracle integrity failure ·
  5 prerequisite failure before any suite ran
USAGE
}

die_usage() { echo "run.sh: ERROR: $*" >&2; usage >&2; exit 2; }

in_list() { local x="$1"; shift; local i
  # shellcheck disable=SC2048
  for i in $*; do [[ "${i}" == "${x}" ]] && return 0; done; return 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --full) FULL=1 ;;
    --suite) [[ $# -ge 2 ]] || die_usage "--suite needs a value";
      in_list "$2" "${ALL_SUITES}" || die_usage "unknown suite: $2"; SUITES+=("$2"); shift ;;
    --suite=*) v="${1#*=}"; in_list "${v}" "${ALL_SUITES}" || die_usage "unknown suite: ${v}"; SUITES+=("${v}") ;;
    --harness) [[ $# -ge 2 ]] || die_usage "--harness needs a value";
      in_list "$2" "${ALL_HARNESSES}" || die_usage "unknown harness: $2"; HARNESSES+=("$2"); shift ;;
    --harness=*) v="${1#*=}"; in_list "${v}" "${ALL_HARNESSES}" || die_usage "unknown harness: ${v}"; HARNESSES+=("${v}") ;;
    --variant) [[ $# -ge 2 ]] || die_usage "--variant needs a value"; VARIANTS+=("$2"); shift ;;
    --variant=*) VARIANTS+=("${1#*=}") ;;
    --keep) KEEP_MODE="keep" ;;
    --keep-on-failure) KEEP_MODE="keep-on-failure" ;;
    --clean) KEEP_MODE="clean" ;;
    --timeout) [[ $# -ge 2 ]] || die_usage "--timeout needs a value"; TIMEOUT="$2"; shift ;;
    --timeout=*) TIMEOUT="${1#*=}" ;;
    --ceiling-usd) [[ $# -ge 2 ]] || die_usage "--ceiling-usd needs a value"; CEILING_USD="$2"; shift ;;
    --ceiling-usd=*) CEILING_USD="${1#*=}" ;;
    --trials) [[ $# -ge 2 ]] || die_usage "--trials needs a value"; TRIALS="$2"; shift ;;
    --trials=*) TRIALS="${1#*=}" ;;
    --pinned) PINNED="true" ;;
    --advisory) PINNED="false" ;;
    --no-trust-seed) NO_TRUST_SEED=1 ;;
    --results-dir) [[ $# -ge 2 ]] || die_usage "--results-dir needs a value"; RESULTS_DIR="$2"; shift ;;
    --results-dir=*) RESULTS_DIR="${1#*=}" ;;
    --bootstrap) DO_BOOTSTRAP=1 ;;
    --list) DO_LIST=1 ;;
    -*) die_usage "unknown option: $1" ;;
    *) die_usage "unexpected argument: $1" ;;
  esac
  shift
done

case "${KEEP_MODE}" in keep|keep-on-failure|clean) ;;
  *) die_usage "bad retention mode: ${KEEP_MODE}" ;; esac
if [[ -z "${PINNED}" ]]; then
  if [[ "${CI:-}" == "true" ]]; then PINNED="true"; else PINNED="false"; fi
fi

if [[ "${FULL}" -eq 1 ]]; then
  read -ra SUITES <<< "${ALL_SUITES}"
  read -ra HARNESSES <<< "${ALL_HARNESSES}"
fi
[[ ${#SUITES[@]} -eq 0 ]] && SUITES=(offline)
[[ ${#HARNESSES[@]} -eq 0 ]] && read -ra HARNESSES <<< "${ALL_HARNESSES}"
[[ ${#VARIANTS[@]} -eq 0 ]] && VARIANTS=(base)
if in_list "all" "${VARIANTS[*]:-}"; then
  VARIANTS=(base)
  for d in "${E2E_ROOT}/fixtures/variants/"*/; do
    [[ -d "${d}" ]] || continue
    VARIANTS+=("$(basename "${d}")")
  done
fi

SUITES_CSV="$(IFS=,; echo "${SUITES[*]}")"
HARN_CSV="$(IFS=,; echo "${HARNESSES[*]}")"
VARIANTS_CSV="$(IFS=,; echo "${VARIANTS[*]}")"

# ---------------------------------------------------------------- bootstrap
if [[ "${DO_BOOTSTRAP}" -eq 1 ]]; then
  PIN_JSONSCHEMA="4.25.1"
  echo "bootstrap: creating ${E2E_ROOT}/.venv"
  python3 -m venv "${E2E_ROOT}/.venv"
  "${E2E_ROOT}/.venv/bin/pip" install --quiet "jsonschema==${PIN_JSONSCHEMA}"
  resolved="$("${E2E_ROOT}/.venv/bin/python" -c 'import jsonschema; print(jsonschema.__version__)')"
  jq -n --arg v "${resolved}" \
    '{jsonschema: $v, bash: "", git: "", jq: "", python3: "",
      offline_budget_seconds: 180,
      bootstrapped_on: ""} | .bootstrapped_on = (now | strftime("%Y-%m-%d"))' \
    > "${E2E_ROOT}/pins/dependencies.json"
  # fill in the ambient tool versions at bootstrap time
  jq --arg bash "${BASH_VERSION}" --arg git "$(git --version | awk '{print $3}')" \
     --arg jq "$(jq --version | sed 's/jq-//')" \
     --arg py "$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])')" \
    '.bash = $bash | .git = $git | .jq = $jq | .python3 = $py' \
    "${E2E_ROOT}/pins/dependencies.json" > "${E2E_ROOT}/pins/dependencies.json.tmp" \
    && mv "${E2E_ROOT}/pins/dependencies.json.tmp" "${E2E_ROOT}/pins/dependencies.json"
  echo "bootstrap: jsonschema ${resolved} (pins/dependencies.json)"
  exit 0
fi

# ---------------------------------------------------------------- list
if [[ "${DO_LIST}" -eq 1 ]]; then
  echo "suites: ${ALL_SUITES}"
  echo -n "variants: base"
  for d in "${E2E_ROOT}/fixtures/variants/"*/; do
    [[ -d "${d}" ]] || continue; echo -n " $(basename "${d}")"
  done
  echo
  echo "harnesses: ${ALL_HARNESSES}"
  echo "checks:"
  grep -rhoE 'record_check id=[a-z0-9._-]+' "${E2E_ROOT}/lib" "${E2E_ROOT}/suites" 2>/dev/null \
    | sed 's/record_check id=//' | sort -u | sed 's/^/  /' || true
  echo "prerequisites: bash 5+, git, jq, python3 3.11+, .venv+jsonschema, claude/codex/opencode CLIs, live credentials"
  exit 0
fi

# ---------------------------------------------------------------- run setup
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
RUN_DIR="${RESULTS_DIR}/${RUN_ID}"
mkdir -p "${RUN_DIR}"
: > "${RUN_DIR}/checks.jsonl"
: > "${RUN_DIR}/capabilities.jsonl"
: > "${RUN_DIR}/workspaces.lst"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# Pre-run digests of the committed fixture and oracle trees (T109, SC-010).
# Digest-based so the check works before the feature's first commit, when
# `git status` on these paths is a no-op for untracked files.
jq -n --arg fix "$("${E2E_ROOT}/tools/digest.py" "${E2E_ROOT}/fixtures" 2>/dev/null || echo unknown)" \
  --arg oracle "$("${E2E_ROOT}/tools/digest.py" "${E2E_ROOT}/oracle" 2>/dev/null || echo unknown)" \
  '{fixture_digest: $fix, oracle_digest: $oracle}' > "${RUN_DIR}/pristine.json"

export E2E_ROOT REPO_ROOT SPECS_DIR
export E2E_RUN_ID="${RUN_ID}" E2E_RUN_DIR="${RUN_DIR}"
export E2E_STARTED_AT="${STARTED_AT}"
export E2E_SUITES="${SUITES_CSV}" E2E_HARNESSES="${HARN_CSV}"
export E2E_VARIANTS="${VARIANTS_CSV}" E2E_PINNED="${PINNED}"
export E2E_NO_TRUST_SEED="${NO_TRUST_SEED}" E2E_KEEP_MODE="${KEEP_MODE}"
export E2E_TIMEOUT="${TIMEOUT}" E2E_CEILING_USD="${CEILING_USD}" E2E_TRIALS="${TRIALS}"
export E2E_RESULTS_DIR="${RESULTS_DIR}"
if [[ "${FULL}" -eq 1 ]]; then E2E_MODE="full";
elif [[ "${SUITES_CSV}" == "offline" ]]; then E2E_MODE="offline";
else E2E_MODE="selected"; fi
export E2E_MODE

# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/prereq.sh" || exit 5

# ---- pins for this run
observe_version() {  # <harness> -> version or empty
  command -v "$1" >/dev/null 2>&1 || return 0
  case "$1" in
    claude) claude --version 2>/dev/null | awk '{print $1}' ;;
    codex) codex --version 2>/dev/null | awk '{print $2}' ;;
    opencode) opencode --version 2>/dev/null | awk '{print $1}' ;;
    devin) echo "" ;;
  esac
  return 0
}
{
  echo "{"
  echo "  \"source_revision\": \"$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)\","
  echo "  \"worktree_digest\": \"$("${E2E_ROOT}/tools/digest.py" "${REPO_ROOT}" 2>/dev/null || echo unknown)\","
  echo "  \"fixture_revision\": \"$("${E2E_ROOT}/tools/digest.py" "${E2E_ROOT}/fixtures" 2>/dev/null || echo unknown)\","
  echo "  \"harnesses\": {"
  first=1
  for h in ${ALL_HARNESSES}; do
    pinned_v="$(jq -r --arg h "${h}" '.harnesses[$h].version // "null"' "${E2E_ROOT}/pins/harnesses.json")"
    [[ "${pinned_v}" == "null" ]] && pinned_json="null" || pinned_json="\"${pinned_v}\""
    obs="$(observe_version "${h}")"
    [[ -n "${obs}" ]] && obs_json="\"${obs}\"" || obs_json="null"
    if [[ "${pinned_json}" != "null" && "${obs_json}" != "null" && "${pinned_v}" == "${obs}" ]]; then
      match="true"; else match="false"; fi
    [[ "${first}" -eq 1 ]] || echo ","
    first=0
    printf '    "%s": {"version_pinned": %s, "version_observed": %s, "pinned_match": %s}' \
      "${h}" "${pinned_json}" "${obs_json}" "${match}"
  done
  echo
  echo "  },"
  echo "  \"dependencies\": $(jq -c '{bash: .bash, git: .git, jq: .jq, python3: .python3, jsonschema: .jsonschema} // {}' "${E2E_ROOT}/pins/dependencies.json" 2>/dev/null || echo '{}'),"
  echo "  \"schemas\": $(jq -c '.schemas' "${E2E_ROOT}/pins/schemas.json" 2>/dev/null || echo '[]')"
  echo "}"
} > "${RUN_DIR}/pins.json"
export E2E_PINS_JSON="${RUN_DIR}/pins.json"
E2E_INVENTORY_VERSION="$(jq -r .inventory_version "${E2E_ROOT}/oracle/capabilities.json" 2>/dev/null || echo 0.0.0)"
export E2E_INVENTORY_VERSION

# ---------------------------------------------------------------- suites
for suite in "${SUITES[@]}"; do
  driver="${E2E_ROOT}/suites/${suite}/run.sh"
  [[ -x "${driver}" ]] || { echo "run.sh: suite driver missing: ${driver}" >&2; exit 2; }
  "${driver}" || true   # suites record their own failures as checks; keep going
done

# ---- post-run assertion: committed fixture and oracle unchanged (T094, T109).
# Digest comparison catches modification even before tests/e2e/ is tracked;
# the git check adds tracked-file coverage once it is.
FIX_BEFORE="$(jq -r .fixture_digest "${RUN_DIR}/pristine.json")"
ORACLE_BEFORE="$(jq -r .oracle_digest "${RUN_DIR}/pristine.json")"
FIX_AFTER="$("${E2E_ROOT}/tools/digest.py" "${E2E_ROOT}/fixtures" 2>/dev/null || echo unknown)"
ORACLE_AFTER="$("${E2E_ROOT}/tools/digest.py" "${E2E_ROOT}/oracle" 2>/dev/null || echo unknown)"
pristine_reason=""
if [[ "${FIX_BEFORE}" == "unknown" || "${FIX_AFTER}" == "unknown" ]]; then
  pristine_reason="committed fixture or oracle tree could not be digested"
elif [[ "${FIX_BEFORE}" != "${FIX_AFTER}" ]]; then
  pristine_reason="committed fixture tree changed during the run (digest mismatch)"
elif [[ "${ORACLE_BEFORE}" != "${ORACLE_AFTER}" ]]; then
  pristine_reason="oracle tree changed during the run (digest mismatch)"
elif [[ -n "$(git -C "${REPO_ROOT}" status --porcelain --untracked-files=no -- tests/e2e/fixtures tests/e2e/oracle 2>/dev/null)" ]]; then
  pristine_reason="committed fixture or oracle tree was modified by the run"
fi
if [[ -n "${pristine_reason}" ]]; then
  # shellcheck disable=SC1091
  source "${E2E_ROOT}/lib/assert.sh"
  if [[ "${SUITES[0]}" == "mutation" ]]; then
    record_check id=run.pristine "suite=${SUITES[0]}" mandatory=true state=failed \
      reason="${pristine_reason}" claim_kind=none \
      mutation_id=run.pristine
  else
    record_check id=run.pristine "suite=${SUITES[0]}" mandatory=true state=failed \
      reason="${pristine_reason}" claim_kind=none
  fi
else
  # shellcheck disable=SC1091
  source "${E2E_ROOT}/lib/assert.sh"
  if [[ "${SUITES[0]}" == "mutation" ]]; then
    record_check id=run.pristine "suite=${SUITES[0]}" mandatory=false state=passed claim_kind=none \
      mutation_id=run.pristine
  else
    record_check id=run.pristine "suite=${SUITES[0]}" mandatory=false state=passed claim_kind=none
  fi
fi

# ---------------------------------------------------------------- verdict
set +e
"${E2E_ROOT}/lib/result.sh"
code=$?
set -e
"${E2E_ROOT}/lib/report.sh" || true

# ---------------------------------------------------------------- retention
if [[ "${KEEP_MODE}" == "clean" ]] || { [[ "${KEEP_MODE}" == "keep-on-failure" ]] && [[ "${code}" -eq 0 ]]; }; then
  while IFS= read -r ws; do
    [[ -n "${ws}" && "${ws}" == /tmp/loom-e2e-* ]] || continue
    rm -rf "${ws}"
    echo "run.sh: removed workspace ${ws}"
  done < "${RUN_DIR}/workspaces.lst"
else
  while IFS= read -r ws; do
    [[ -n "${ws}" ]] || continue
    echo "run.sh: kept workspace ${ws}"
  done < "${RUN_DIR}/workspaces.lst"
fi

exit "${code}"
