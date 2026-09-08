#!/usr/bin/env bash
# suites/live/no-change.sh — invoke the skill against an already up-to-date
# workspace and assert no artifact modification (T064, FR-029). Sourced.
: "${E2E_RUN_DIR:?}" "${E2E_ROOT:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh" 2>/dev/null || true

live_no_change() {  # <workspace> <evidence-dir>
  local ws="$1" evdir="$2"
  local before after
  # If scenario 1 produced no adapters there is nothing to verify unchanged:
  # fail loudly instead of crashing the driver on missing paths.
  if [[ ! -f "${ws}/opencode.json" || ! -d "${ws}/.codex" ]]; then
    record_check id=live.no-change suite=live mandatory=true state=failed \
      reason="scenario 1 produced no adapters — nothing to verify unchanged" \
      claim_kind=behaviour-probe harness=claude
    return 0
  fi
  before="$("${E2E_ROOT}/tools/digest.py" "${ws}/.codex" "${ws}/.devin" \
    "${ws}/opencode.json" | sha256sum | awk '{print $1}')"
  invoke_claude "${ws}" "${E2E_ROOT}/suites/live/prompts/no-change.txt" \
    "${evdir}" "live-2"
  after="$("${E2E_ROOT}/tools/digest.py" "${ws}/.codex" "${ws}/.devin" \
    "${ws}/opencode.json" | sha256sum | awk '{print $1}')"
  # Retain the transcript through the redaction gate; consumption numbers
  # carry no secrets and are referenced in place.
  local ev="live/live-2.consumption.json"
  if rp="$(retain_file live.no-change "${evdir}/live-2.stream-json.jsonl" live-2.stream-json.jsonl 2>/dev/null)"; then
    ev="${ev},${rp}"
  fi
  if [[ "${INVOKE_EXIT}" -ne 0 ]]; then
    record_check id=live.no-change suite=live mandatory=true state=failed \
      reason="no-change invocation exited ${INVOKE_EXIT}" \
      claim_kind=behaviour-probe harness=claude evidence="${ev}"
  elif [[ "${before}" == "${after}" ]]; then
    record_check id=live.no-change suite=live mandatory=true state=passed \
      claim_kind=behaviour-probe harness=claude \
      interface="claude -p --output-format stream-json" evidence="${ev}"
  else
    record_check id=live.no-change suite=live mandatory=true state=failed \
      reason="skill run modified artifacts in an up-to-date workspace" \
      claim_kind=behaviour-probe harness=claude evidence="${ev}"
  fi
}
