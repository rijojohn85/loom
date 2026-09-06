#!/usr/bin/env bash
# suites/intent/hook-order.sh — matching hooks run in the intended order, the
# non-matching hook does not run (T088). Reads the fixture audit log.
# Claude-only for execution; codex/opencode resolve to their reviewed
# hook gaps (approved-gap, never counted as support).
# Usage: <ws> <evdir>
set -euo pipefail
E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${E2E_RUN_DIR:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/evidence.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/intent/trials.sh"

WS="$1"; EVDIR="$2"
SC="hook-order"
printf 'Create the file SCENARIO_NOTES.md in this project with exactly this one line, using the Edit or Write tool: hook-order scenario marker. Do not run any shell commands.\n' \
  > "${EVDIR}/${SC}.prompt.txt"

if intent_authed claude; then
  before=0
  [[ -f "${WS}/hooks/audit.log" ]] && before="$(wc -l < "${WS}/hooks/audit.log" | tr -d ' ')"
  tag="${SC}.claude.t1"
  invoke_target claude "${WS}" "${EVDIR}" "${tag}" "${EVDIR}/${SC}.prompt.txt"
  if ! claude_auth_blocked "intent.${SC}.claude"; then
    after=0
    [[ -f "${WS}/hooks/audit.log" ]] && after="$(wc -l < "${WS}/hooks/audit.log" | tr -d ' ')"
    newlog="${EVDIR}/${SC}.new-audit.log"
    if [[ "${after}" -gt "${before}" ]]; then
      tail -n "+$((before + 1))" "${WS}/hooks/audit.log" > "${newlog}"
    else
      : > "${newlog}"
    fi
    # Expected: pre-write, pre-write-check, post-write in order (+ Stop at end);
    # no PostToolUse-Bash entry among the new lines (the non-matching hook).
    seq="$(grep -E "PreToolUse Write|PostToolUse Write|Stop " "${newlog}" 2>/dev/null \
      | sed -E 's/^[0-9]+ //' | tr '\n' ' ' || true)"
    state="failed"; reason=""
    if grep -q "PostToolUse Bash" "${newlog}" 2>/dev/null; then
      reason="non-matching Bash hook fired for a file write"
    elif [[ -f "${WS}/SCENARIO_NOTES.md" ]] \
      && [[ "${seq}" == *"PreToolUse Write pre-write.sh"* ]] \
      && [[ "${seq}" == *"PreToolUse Write pre-write-check.sh"* ]] \
      && [[ "${seq}" == *"PostToolUse Write post-write.sh"* ]]; then
      # Order assertion on the three Write-hook entries.
      order="$(grep -E "PreToolUse Write|PostToolUse Write" "${newlog}" \
        | sed -E 's/.*(PreToolUse Write |PostToolUse Write )//' | tr '\n' ',' || true)"
      if [[ "${order}" == "pre-write.sh,pre-write-check.sh,post-write.sh," ]]; then
        state="passed"
        reason="matching hooks ran in declared order; non-matching Bash hook silent"
      else
        reason="hook order violated: ${order}"
      fi
    else
      reason="expected hook entries missing (file written: $([[ -f "${WS}/SCENARIO_NOTES.md" ]] && echo yes || echo no))"
    fi
    sum_consumption "${EVDIR}" "${SC}.claude" "${tag}"
    ev="intent/${SC}.claude.consumption.json"
    if rp="$(retain_file "intent.${SC}.claude" "${EVDIR}/${tag}.stream-json.jsonl" "${tag}.stream-json.jsonl" 2>/dev/null)"; then
      ev="${ev},${rp}"
    fi
    if rp2="$(retain_file "intent.${SC}.claude" "${newlog}" "${SC}.audit-slice.log" 2>/dev/null)"; then
      ev="${ev},${rp2}"
    fi
    attempts="$(jq -c -n --arg s "${state}" --arg r "${reason}" \
      --arg e "${ev}" '[{n: 1, state: $s, reason: $r}]')"
    record_check id="intent.${SC}.claude" suite=intent mandatory=true \
      "state=${state}" "reason=${reason}" \
      claim_kind=behaviour-probe harness=claude \
      interface="claude -p hook audit" "evidence=${ev}" \
      "attempts_json=${attempts}"
  fi
else
  record_check id="intent.${SC}.claude" suite=intent mandatory=true \
    state=blocked reason="no live credentials" claim_kind=none harness=claude
fi
# No hook mechanism: the intent resolves to the reviewed gaps (T092-adjacent).
for h in codex opencode; do
  record_check id="intent.${SC}.${h}" suite=intent mandatory=true \
    state=approved-gap "gap_id=gap.${h}.hooks-pre" \
    reason="hook intent is a reviewed gap on ${h}" \
    claim_kind=local-structural "harness=${h}"
done
record_check id="intent.${SC}.devin" suite=intent mandatory=false \
  state=skipped reason="deferred target" claim_kind=none harness=devin
