#!/usr/bin/env bash
# suites/intent/context-influence.sh — project context demonstrably
# influences the task it is claimed to influence (T089, FR-050).
# Baseline (Claude) first; codex via the deterministic prompt-input probe
# (no model spend); opencode model-observed when credentialed.
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
SC="context-influence"
COUNT="$(jq -r .trials.count "${E2E_ROOT}/oracle/scenarios/${SC}.json")"
THRESH="$(jq -r .trials.threshold "${E2E_ROOT}/oracle/scenarios/${SC}.json")"
[[ -n "${E2E_TRIALS:-}" ]] && COUNT="${E2E_TRIALS}"
printf 'What project-specific rules govern how you make edits here? Cite the exact rule text.\n' \
  > "${EVDIR}/${SC}.prompt.txt"

_ctx_ok() {  # <stream> — rule quoted (paraphrase-tolerant)
  grep -qi "deny" "$1" 2>/dev/null && grep -Eqi "gap|reviewed" "$1" 2>/dev/null
}

# Baseline: Claude, bounded trials.
if ! intent_authed claude; then
  record_check id="intent.${SC}.claude" suite=intent mandatory=true \
    state=blocked reason="no live credentials" claim_kind=none harness=claude
  BASELINE_OK=0
else
  passed=0; attempts=(); ctx_blocked=0
  for ((n = 1; n <= COUNT; n++)); do
    tag="${SC}.claude.t${n}"
    invoke_target claude "${WS}" "${EVDIR}" "${tag}" "${EVDIR}/${SC}.prompt.txt"
    if claude_auth_blocked "intent.${SC}.claude"; then ctx_blocked=1; break; fi
    if _ctx_ok "${EVDIR}/${tag}.stream-json.jsonl"; then
      passed=$((passed + 1)); st="passed"; rs="context quoted from project configuration"
    else
      st="failed"
      if [[ "${INVOKE_EXIT}" -ne 0 ]]; then
        rs="model task failure (exit ${INVOKE_EXIT}) — harness ran, task failed"
      else
        rs="context not quoted (exit 0 — configuration loading or enforcement failure, not a model failure)"
      fi
    fi
    attempts+=("$(jq -c -n --argjson n "${n}" --arg s "${st}" --arg r "${rs}" \
      --arg e "intent/${tag}.stream-json.jsonl" \
      '{n: $n, state: $s, reason: $r, evidence: [$e]}')")
  done
  if [[ "${ctx_blocked}" == "1" ]]; then
    BASELINE_OK=0
  else
    state="failed"; [[ "${passed}" -ge "${THRESH}" ]] && state="passed"
    # shellcheck disable=SC2046  # intentional splitting of the tag list
    sum_consumption "${EVDIR}" "${SC}.claude" \
      $(for ((n = 1; n <= COUNT; n++)); do echo "${SC}.claude.t${n}"; done)
    ev="intent/${SC}.claude.consumption.json"
    for ((n = 1; n <= COUNT; n++)); do
      if rp="$(retain_file "intent.${SC}.claude" "${EVDIR}/${SC}.claude.t${n}.stream-json.jsonl" "${SC}.claude.t${n}.stream-json.jsonl" 2>/dev/null)"; then
        ev="${ev},${rp}"
      fi
    done
    record_check id="intent.${SC}.claude" suite=intent mandatory=true \
      "state=${state}" "reason=context quoted ${passed}/${COUNT} trials (threshold ${THRESH})" \
      claim_kind=behaviour-probe harness=claude \
      interface="claude -p context probe" "evidence=${ev}" \
      "attempts_json=$(printf '%s\n' "${attempts[@]}" | jq -c -s .)"
    if [[ "${state}" == "passed" ]]; then BASELINE_OK=1; else BASELINE_OK=0; fi
  fi
fi

# Codex: deterministic prompt-input probe (no model spend).
if [[ " ${E2E_HARNESSES:-} " == *" codex "* ]]; then
  # shellcheck disable=SC1091
  source "${E2E_ROOT}/probes/codex.sh"
  payload="$(probe_context_loaded "${WS}" || true)"
  pstatus="$(jq -r .status <<<"${payload}")"
  if [[ "${pstatus}" == "ok" ]]; then
    record_check id="intent.${SC}.codex" suite=intent mandatory=true \
      state=passed claim_kind=harness-loader-probe harness=codex \
      version="$(jq -r .harness_version_observed <<<"${payload}")" \
      interface="codex debug prompt-input" \
      reason="AGENTS.md rule present in model-visible prompt"
  else
    record_check id="intent.${SC}.codex" suite=intent mandatory=true \
      state=failed reason="$(jq -r .reason <<<"${payload}")" \
      claim_kind=harness-loader-probe harness=codex \
      interface="codex debug prompt-input"
  fi
fi

# opencode: model-observed when credentialed.
if [[ " ${E2E_HARNESSES:-} " == *" opencode "* ]]; then
  if ! intent_authed opencode; then
    record_check id="intent.${SC}.opencode" suite=intent mandatory=true \
      state=blocked reason="no opencode model auth in this environment" \
      claim_kind=none harness=opencode
  elif [[ "${BASELINE_OK}" != "1" ]]; then
    record_check id="intent.${SC}.opencode" suite=intent mandatory=true \
      state=blocked reason="baseline did not express the intended behaviour — targets not judged" \
      claim_kind=none harness=opencode
  else
    passed=0; attempts=()
    for ((n = 1; n <= COUNT; n++)); do
      tag="${SC}.opencode.t${n}"
      invoke_target opencode "${WS}" "${EVDIR}" "${tag}" "${EVDIR}/${SC}.prompt.txt"
      if _ctx_ok "${EVDIR}/${tag}.stream-json.jsonl"; then
        passed=$((passed + 1)); st="passed"; rs="context quoted"
      else
        st="failed"
        if [[ "${INVOKE_EXIT}" -ne 0 ]]; then
          rs="model task failure (exit ${INVOKE_EXIT})"
        else
          rs="context not quoted"
        fi
      fi
      attempts+=("$(jq -c -n --argjson n "${n}" --arg s "${st}" --arg r "${rs}" \
        --arg e "intent/${tag}.stream-json.jsonl" \
        '{n: $n, state: $s, reason: $r, evidence: [$e]}')")
    done
    state="failed"; [[ "${passed}" -ge "${THRESH}" ]] && state="passed"
    # shellcheck disable=SC2046  # intentional splitting of the tag list
    sum_consumption "${EVDIR}" "${SC}.opencode" \
      $(for ((n = 1; n <= COUNT; n++)); do echo "${SC}.opencode.t${n}"; done)
    record_check id="intent.${SC}.opencode" suite=intent mandatory=true \
      "state=${state}" "reason=context quoted ${passed}/${COUNT} trials" \
      claim_kind=behaviour-probe harness=opencode \
      interface="opencode run context probe" \
      "evidence=intent/${SC}.opencode.consumption.json" \
      "attempts_json=$(printf '%s\n' "${attempts[@]}" | jq -c -s .)"
  fi
fi
record_check id="intent.${SC}.devin" suite=intent mandatory=false \
  state=skipped reason="deferred target" claim_kind=none harness=devin
