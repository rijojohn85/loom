#!/usr/bin/env bash
# suites/offline/smoke.sh — invoke tests/smoke.sh unmodified (T038, FR-005).
# Its result is a single named check. smoke.sh stays independently runnable.
set -euo pipefail
E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${E2E_RUN_DIR:?}" "${REPO_ROOT:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"

start="$(date +%s%3N 2>/dev/null || date +%s)"
if "${REPO_ROOT}/tests/smoke.sh" >"${E2E_RUN_DIR}/offline/smoke.log" 2>&1; then
  state="passed"; reason=""
else
  state="failed"; reason="tests/smoke.sh reported failures (see offline/smoke.log)"
fi
finish="$(date +%s%3N 2>/dev/null || date +%s)"
dur=0; [[ "${start}" =~ ^[0-9]+$ && "${finish}" =~ ^[0-9]+$ ]] && dur=$((finish - start))
[[ "${dur}" -gt 2000000 ]] && dur=0
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/evidence.sh"
cp "${E2E_RUN_DIR}/offline/smoke.log" "${E2E_RUN_DIR}/evidence/offline.smoke.log" 2>/dev/null \
  || { mkdir -p "${E2E_RUN_DIR}/evidence"; cp "${E2E_RUN_DIR}/offline/smoke.log" "${E2E_RUN_DIR}/evidence/offline.smoke.log"; }
record_check id=offline.smoke suite=offline mandatory=true state="${state}" \
  reason="${reason}" claim_kind=local-structural interface="tests/smoke.sh" \
  duration_ms="${dur}"
