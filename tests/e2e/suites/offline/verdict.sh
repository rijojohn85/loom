#!/usr/bin/env bash
# suites/offline/verdict.sh — the offline-only verdict guard (T048, FR-004).
# Asserts (a) lib/result.sh maps an offline-only run to
# `offline-pass (offline layer only — not full end-to-end)` with a required
# verdict_note, and (b) the unqualified success token never appears in
# anything the runner prints (scripts that produce stdout).
set -euo pipefail
E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${E2E_RUN_DIR:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/mutation/validators.sh"

reason=""
grep -q 'VERDICT="offline-pass"' "${E2E_ROOT}/lib/result.sh" \
  || reason="result.sh never computes an offline-pass verdict"
if [[ -z "${reason}" ]]; then
  grep -q 'offline layer only' "${E2E_ROOT}/lib/result.sh" \
    || reason="result.sh offline verdict lacks the required offline-only note"
fi
if [[ -z "${reason}" ]]; then
  grep -q 'verdict_note' "${E2E_ROOT}/lib/result.sh" \
    || reason="result.sh does not emit a verdict_note"
fi
if [[ -z "${reason}" ]]; then
  # Strip qualified verdict tokens, then fail on a standalone success word.
  bad="$(v_verdict_scan "${E2E_ROOT}/run.sh" "${E2E_ROOT}/lib/result.sh" \
    "${E2E_ROOT}/lib/report.sh" "${E2E_ROOT}/suites/offline/" || true)"
  if [[ -n "${bad}" ]]; then
    reason="unqualified success token in runner output paths: $(echo "${bad}" | head -2 | tr '\n' ';')"
  fi
fi

if [[ -z "${reason}" ]]; then
  record_check id=offline.verdict-guard suite=offline mandatory=true \
    state=passed claim_kind=local-structural reason=""
else
  record_check id=offline.verdict-guard suite=offline mandatory=true \
    state=failed reason="${reason}" claim_kind=local-structural
fi
