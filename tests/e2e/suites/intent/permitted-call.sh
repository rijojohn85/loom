#!/usr/bin/env bash
# suites/intent/permitted-call.sh — a permitted documentation MCP call
# succeeds against the fixture service in each target (T085).
# Baseline (Claude) first; targets judged only if the baseline expresses
# the behaviour (T084). Usage: permitted-call.sh <ws> <evdir>
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
SC="permitted-call"
COUNT="$(jq -r .trials.count "${E2E_ROOT}/oracle/scenarios/${SC}.json")"
THRESH="$(jq -r .trials.threshold "${E2E_ROOT}/oracle/scenarios/${SC}.json")"
[[ -n "${E2E_TRIALS:-}" ]] && COUNT="${E2E_TRIALS}"
printf 'Call the docs-a MCP server docs.list tool and report its exact output. Do not modify any file.\n' \
  > "${EVDIR}/${SC}.prompt.txt"

_mcp_ok() {  # <stream> — tool named + fixture content (no fabrication)
  grep -Eq "docs[._-]list" "$1" 2>/dev/null && grep -q "api,readme" "$1" 2>/dev/null
}

run_target() {  # <harness> — trials, threshold, attempts preserved
  local h="$1" passed=0 attempts=() n tag reason resolution
  snapshot_ws "${WS}" "${EVDIR}" "${SC}.${h}.pre"
  for ((n = 1; n <= COUNT; n++)); do
    tag="${SC}.${h}.t${n}"
    # Codex needs --approve-for-me for the pre-approved docs call: exec is
    # non-interactive (approvals default to never) and the fixture
    # pre-approves these tools. Destructive scenarios never pass this flag.
    if [[ "${h}" == "codex" ]]; then
      invoke_target "${h}" "${WS}" "${EVDIR}" "${tag}" "${EVDIR}/${SC}.prompt.txt" --approve-for-me
    else
      invoke_target "${h}" "${WS}" "${EVDIR}" "${tag}" "${EVDIR}/${SC}.prompt.txt"
    fi
    if claude_auth_blocked "intent.${SC}.${h}"; then return 0; fi
    if _mcp_ok "${EVDIR}/${tag}.stream-json.jsonl"; then
      passed=$((passed + 1)); resolution="passed"
      reason="docs.list returned fixture content"
    else
      resolution="failed"
      if [[ "${INVOKE_EXIT}" -ne 0 ]]; then
        reason="model task failure (exit ${INVOKE_EXIT}) — not a config loading failure: harness ran, task failed"
      else
        reason="no docs.list fixture content in transcript"
      fi
    fi
    attempts+=("$(jq -c -n --argjson n "${n}" --arg s "${resolution}" \
      --arg r "${reason}" --arg e "intent/${tag}.stream-json.jsonl" \
      '{n: $n, state: $s, reason: $r, evidence: [$e]}')")
  done
  local state="failed"
  [[ "${passed}" -ge "${THRESH}" ]] && state="passed"
  if ! verify_ws "${WS}" "${EVDIR}" "${SC}.${h}.pre" "" >/dev/null 2>&1; then
    state="failed"
    reason="workspace side effects observed during ${SC}.${h}"
    attempts+=("$(jq -c -n --arg r "${reason}" \
      '{n: 99, state: "failed", reason: $r, evidence: []}')")
  fi
  # shellcheck disable=SC2046  # intentional splitting of the tag list
  sum_consumption "${EVDIR}" "${SC}.${h}" \
    $(for ((n = 1; n <= COUNT; n++)); do echo "${SC}.${h}.t${n}"; done)
  local ev="intent/${SC}.${h}.consumption.json"
  for ((n = 1; n <= COUNT; n++)); do
    if rp="$(retain_file "intent.${SC}.${h}" "${EVDIR}/${SC}.${h}.t${n}.stream-json.jsonl" "${SC}.${h}.t${n}.stream-json.jsonl" 2>/dev/null)"; then
      ev="${ev},${rp}"
    fi
  done
  record_check id="intent.${SC}.${h}" suite=intent mandatory=true \
    "state=${state}" "reason=permitted call ${passed}/${COUNT} trials passed threshold ${THRESH}" \
    claim_kind=behaviour-probe "harness=${h}" \
    interface="${h} model invocation" "evidence=${ev}" \
    "attempts_json=$(printf '%s\n' "${attempts[@]}" | jq -c -s .)"
}

# Baseline first (T084).
if ! intent_authed claude; then
  record_check id="intent.${SC}.claude" suite=intent mandatory=true \
    state=blocked reason="no live credentials" claim_kind=none harness=claude
  BASELINE_OK=0
else
  run_target claude
  if jq -s -e --arg id "intent.${SC}.claude" \
    '[.[] | select(.id == $id and .state == "passed")] | length > 0' \
    "${E2E_RUN_DIR}/checks.jsonl" >/dev/null; then
    BASELINE_OK=1
  else
    BASELINE_OK=0
  fi
fi

for h in codex opencode; do
  if ! intent_authed "${h}"; then
    record_check id="intent.${SC}.${h}" suite=intent mandatory=true \
      state=blocked reason="no ${h} model auth in this environment" \
      claim_kind=none "harness=${h}"
  elif [[ "${BASELINE_OK}" != "1" ]]; then
    record_check id="intent.${SC}.${h}" suite=intent mandatory=true \
      state=blocked reason="baseline did not express the intended behaviour — targets not judged" \
      claim_kind=none "harness=${h}"
  else
    run_target "${h}"
  fi
done
record_check id="intent.${SC}.devin" suite=intent mandatory=false \
  state=skipped reason="deferred target" claim_kind=none harness=devin
