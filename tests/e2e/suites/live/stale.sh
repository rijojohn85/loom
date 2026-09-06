#!/usr/bin/env bash
# suites/live/stale.sh — the stale/schema-change scenario (T065, FR-029/031).
# Ages a spec pack past spec_pack_max_age_days, invokes the skill, and
# records the refreshed pack diff and any emitter diff with its
# justification. Sourced.
: "${E2E_RUN_DIR:?}" "${E2E_ROOT:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/evidence.sh" 2>/dev/null || true

live_stale() {  # <workspace> <evidence-dir>
  local ws="$1" evdir="$2"
  local pack="${ws}/agent/harness-specs/devin.md"
  cp "${pack}" "${evdir}/stale.pack.before.md"
  sed -i 's/^generated: .*/generated: 2020-01-01/' "${pack}"
  invoke_claude "${ws}" "${E2E_ROOT}/suites/live/prompts/stale.txt" \
    "${evdir}" "live-3"
  local stream="${evdir}/live-3.stream-json.jsonl"
  cp "${pack}" "${evdir}/stale.pack.after.md"
  diff -u "${evdir}/stale.pack.before.md" "${evdir}/stale.pack.after.md" \
    > "${evdir}/stale.pack.diff" || true
  local ev="live/live-3.consumption.json"
  if rp="$(retain_file live.schema-change "${evdir}/live-3.stream-json.jsonl" live-3.stream-json.jsonl 2>/dev/null)"; then
    ev="${ev},${rp}"
  fi
  if [[ "${INVOKE_EXIT}" -ne 0 ]]; then
    record_check id=live.schema-change suite=live mandatory=true state=failed \
      reason="stale-scenario invocation exited ${INVOKE_EXIT}" \
      claim_kind=behaviour-probe harness=claude evidence="${ev}"
  elif grep -q "days old" "${stream}" 2>/dev/null; then
    record_check id=live.schema-change suite=live mandatory=true state=passed \
      claim_kind=behaviour-probe harness=claude \
      interface="claude -p --output-format stream-json" evidence="${ev}"
  else
    record_check id=live.schema-change suite=live mandatory=true state=failed \
      reason="skill run did not surface the staleness warning" \
      claim_kind=behaviour-probe harness=claude evidence="${ev}"
  fi
}
