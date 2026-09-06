#!/usr/bin/env bash
# lib/result.sh — emit results.json, print the verdict block, choose exit code.
#
# Reads $E2E_RUN_DIR/checks.jsonl and capabilities.jsonl. The verdict is
# computed from check states, never asserted by hand (FR-004, FR-053).
# A full-E2E verdict is refused unless every layer ran (mode == full).
#
# Env in: E2E_RUN_DIR, E2E_RUN_ID, E2E_STARTED_AT, E2E_MODE
#   (offline|selected|full), E2E_SUITES (csv), E2E_HARNESSES (csv),
#   E2E_INVENTORY_VERSION, E2E_PINS_JSON (path), E2E_RESULTS_PATH (for stdout).
# Prints the per-check lines + verdict block to stdout.
# Exit: 0 all mandatory passed · 1 a check failed · 3 mandatory
#   blocked/skipped · 4 oracle-integrity failure.
set -euo pipefail
: "${E2E_RUN_DIR:?}" "${E2E_RUN_ID:?}" "${E2E_STARTED_AT:?}"
: "${E2E_MODE:?}" "${E2E_SUITES:?}" "${E2E_HARNESSES:?}"
: "${E2E_INVENTORY_VERSION:?}" "${E2E_PINS_JSON:?}"

RUN_DIR="${E2E_RUN_DIR}"
touch "${RUN_DIR}/checks.jsonl" "${RUN_DIR}/capabilities.jsonl"
FINISHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

count_checks() {  # <state> -> n
  jq -s --arg s "$1" '[.[] | select(.state == $s)] | length' \
    "${RUN_DIR}/checks.jsonl"
}
count_caps() {  # <state> -> n
  jq -s --arg s "$1" '[.[] | select(.state == $s)] | length' \
    "${RUN_DIR}/capabilities.jsonl" 2>/dev/null || echo 0
}

P_PASSED="$(count_checks passed)"; P_FAILED="$(count_checks failed)"
P_GAP="$(count_checks approved-gap)"; P_SKIP="$(count_checks skipped)"
P_BLOCK="$(count_checks blocked)"
C_PRES="$(count_caps preserved)"; C_COMP="$(count_caps verified-compensated)"
C_GAP="$(count_caps approved-gap)"; C_FAIL="$(count_caps failed)"
C_UNVER="$(count_caps unverified)"

MAND_FAIL="$(jq -s '[.[] | select(.mandatory and .state == "failed") | .id]' \
  "${RUN_DIR}/checks.jsonl")"
MAND_NOTRUN="$(jq -s '[.[] | select(.mandatory and (.state == "blocked" or .state == "skipped")) | .id]' \
  "${RUN_DIR}/checks.jsonl")"
N_MAND_FAIL="$(jq 'length' <<<"${MAND_FAIL}")"
N_MAND_NOTRUN="$(jq 'length' <<<"${MAND_NOTRUN}")"
ORACLE_BAD="$(jq -s '[.[] | select(.id == "oracle.integrity" and .state == "failed")] | length' \
  "${RUN_DIR}/checks.jsonl")"

VERDICT=""; NOTE=""
if [[ "${ORACLE_BAD}" -gt 0 ]]; then
  VERDICT="oracle-integrity-failure"
  NOTE="the oracle tree changed during the run — expectations are suspect, nothing else may be trusted."
elif [[ "${N_MAND_FAIL}" -gt 0 ]]; then
  VERDICT="failed"
  NOTE="at least one mandatory check failed."
elif [[ "${N_MAND_NOTRUN}" -gt 0 ]]; then
  VERDICT="blocked"
  NOTE="at least one mandatory check was blocked or skipped — see mandatory_not_run."
elif [[ "${E2E_MODE}" == "full" ]]; then
  VERDICT="full-e2e-pass"
  NONMAND_NOTRUN="$(jq -s '[.[] | select((.mandatory | not) and (.state == "blocked" or .state == "skipped"))] | length' \
    "${RUN_DIR}/checks.jsonl")"
  if [[ "${NONMAND_NOTRUN}" -gt 0 ]]; then
    NOTE="all mandatory checks passed; ${NONMAND_NOTRUN} non-mandatory check(s) blocked or skipped (deferred targets — outside every passing total)."
  fi
else
  if [[ "${E2E_MODE}" == "offline" ]]; then
    VERDICT="offline-pass"
    NOTE="offline layer only — not full end-to-end. Live skill execution, harness conformance and intent behaviour were not run."
  else
    VERDICT="partial"
    NOTE="selected suites only (${E2E_SUITES}) — not full end-to-end."
  fi
fi

# suites/harnesses csv -> json arrays
SUITES_JSON="$(jq -n --arg s "${E2E_SUITES}" '$s | split(",") | map(select(. != ""))')"
HARN_JSON="$(jq -n --arg s "${E2E_HARNESSES}" '$s | split(",") | map(select(. != ""))')"

jq -n \
  --arg run_id "${E2E_RUN_ID}" --arg started "${E2E_STARTED_AT}" \
  --arg finished "${FINISHED_AT}" --arg mode "${E2E_MODE}" \
  --arg inv "${E2E_INVENTORY_VERSION}" \
  --argjson suites "${SUITES_JSON}" --argjson harnesses "${HARN_JSON}" \
  --slurpfile pins "${E2E_PINS_JSON}" \
  --slurpfile checks "${RUN_DIR}/checks.jsonl" \
  --slurpfile caps "${RUN_DIR}/capabilities.jsonl" \
  --argjson p "${P_PASSED}" --argjson f "${P_FAILED}" \
  --argjson g "${P_GAP}" --argjson sk "${P_SKIP}" --argjson b "${P_BLOCK}" \
  --argjson cp "${C_PRES}" --argjson cc "${C_COMP}" --argjson cg "${C_GAP}" \
  --argjson cf "${C_FAIL}" --argjson cu "${C_UNVER}" \
  --argjson notrun "${MAND_NOTRUN}" \
  --arg verdict "${VERDICT}" --arg note "${NOTE}" \
  --arg workspace "workspace.json" '
  {
    run_id: $run_id, started_at: $started, finished_at: $finished,
    mode: $mode, inventory_version: $inv,
    suites_selected: $suites, harnesses_selected: $harnesses,
    workspace: $workspace, pins: $pins[0],
    checks: $checks, capabilities: $caps,
    summary: {
      checks: {passed: $p, failed: $f, approved_gap: $g,
               skipped: $sk, blocked: $b},
      capabilities: {preserved: $cp, verified_compensated: $cc,
                     approved_gap: $cg, failed: $cf, unverified: $cu},
      mandatory_not_run: $notrun
    },
    verdict: $verdict
  } + (if $note != "" then {verdict_note: $note} else {} end)
  ' > "${RUN_DIR}/results.json"

# ---- stdout (contract: one line per check, then a verdict block)
jq -s -r '.[] | "\(.state)  \(.id)\(if .harness then "  [\(.harness)]" else "" end)\(if .reason then "  \(.reason)" else "" end)"' \
  "${RUN_DIR}/checks.jsonl"
echo "verdict: ${VERDICT}$( [[ -n "${NOTE}" ]] && printf ' (%s)' "${NOTE}" || true )"
echo "checks: ${P_PASSED} passed · ${P_FAILED} failed · ${P_GAP} approved-gap · ${P_BLOCK} blocked · ${P_SKIP} skipped"
echo "capabilities: ${C_PRES} preserved · ${C_COMP} verified-compensated · ${C_GAP} approved-gap · ${C_FAIL} failed · ${C_UNVER} unverified"
echo "results: ${RUN_DIR}/results.json"

if [[ "${VERDICT}" == "oracle-integrity-failure" ]]; then exit 4; fi
if [[ "${N_MAND_FAIL}" -gt 0 ]]; then exit 1; fi
if [[ "${N_MAND_NOTRUN}" -gt 0 ]]; then exit 3; fi
exit 0
