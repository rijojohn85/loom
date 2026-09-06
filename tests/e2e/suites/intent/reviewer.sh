#!/usr/bin/env bash
# suites/intent/reviewer.sh — optional LLM intent reviewer (T091, FR-052).
# Reads its rubric from oracle/reviewer-rubric.md, requires cited trace and
# artifact references, records model + consumption, and stays supplementary:
# it never overrides a deterministic failure. Opt-in via
# E2E_INTENT_REVIEWER=1; otherwise a single skipped marker is recorded.
# Usage: reviewer.sh <ws> <evdir> <scenario>...
set -euo pipefail
E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${E2E_RUN_DIR:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/live/invoke.sh"

WS="$1"; EVDIR="$2"; shift 2
if [[ "${E2E_INTENT_REVIEWER:-0}" != "1" ]]; then
  record_check id=intent.reviewer suite=intent mandatory=false state=skipped \
    reason="opt-in reviewer disabled (E2E_INTENT_REVIEWER=1 to enable)" \
    claim_kind=none
  exit 0
fi
if ! [[ "${E2E_HAVE_CREDS:-0}" == "1" ]]; then
  record_check id=intent.reviewer suite=intent mandatory=false state=skipped \
    reason="no live credentials for the reviewer" claim_kind=none
  exit 0
fi

for sc in "$@"; do
  # Stage a review bundle INSIDE the workspace (the reviewer's --add-dir
  # confinement): the scenario transcripts, consumption records, and the
  # recorded checks excerpt. Paths below are bundle-relative.
  bundle="${WS}/review-bundle/${sc}"
  mkdir -p "${bundle}"
  cp "${EVDIR}"/${sc}.*.stream-json.jsonl "${bundle}/" 2>/dev/null || true
  cp "${EVDIR}"/${sc}.*.consumption.json "${bundle}/" 2>/dev/null || true
  jq -c -s --arg sc "intent.${sc}." \
    '[.[] | select(.id | startswith($sc))]' \
    "${E2E_RUN_DIR}/checks.jsonl" > "${bundle}/checks.json" 2>/dev/null || echo '[]' > "${bundle}/checks.json"
  prompt="${EVDIR}/reviewer.${sc}.prompt.txt"
  {
    echo "You are reviewing an end-to-end test trace against the rubric below."
    echo
    cat "${E2E_ROOT}/oracle/reviewer-rubric.md"
    echo
    echo "Scenario: ${sc}. Evidence bundle: review-bundle/${sc}/ (transcripts, consumption files, checks.json)."
    echo "Cite bundle-relative trace and artifact paths. Output the rubric JSON object only."
  } > "${prompt}"
  invoke_claude "${WS}" "${prompt}" "${EVDIR}" "reviewer.${sc}"
  out="${EVDIR}/reviewer.${sc}.stream-json.jsonl"
  # The verdict arrives escaped inside the result text — decode first.
  verdict="$(jq -s -r '[.. | objects | .result? // empty] | join("\n")' \
    "${out}" 2>/dev/null \
    | grep -Eo '"verdict"[ ]*:[ ]*"(supported|contested|refused)"' \
    | tail -1 | grep -Eo '(supported|contested|refused)' || true)"
  [[ -z "${verdict}" ]] && verdict="refused"
  record_check id="intent.reviewer.${sc}" suite=intent mandatory=false \
    "state=passed" "reason=reviewer verdict: ${verdict} (supplementary — overrides nothing)" \
    claim_kind=behaviour-probe harness=claude \
    interface="claude -p rubric review" \
    "evidence=intent/reviewer.${sc}.consumption.json"
done
