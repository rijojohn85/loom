#!/usr/bin/env bash
# suites/live/invoke.sh — one instrumented Claude Code invocation (sourced).
#
#   invoke_claude <workspace> <prompt-file> <evidence-dir> <tag>
# Runs claude -p with the contract flags (T060), tees stream-json, prints
# progress with running consumption, enforces the opt-in --timeout, records
# the exit status, and writes <evidence-dir>/<tag>.consumption.json.
# Unbounded by default (clarified decision, T063); ceilings are opt-in.
# Sets INVOKE_EXIT, INVOKE_STREAM (<tag>.stream-json.jsonl path).
: "${E2E_RUN_DIR:?}" "${E2E_ROOT:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/isolate.sh" 2>/dev/null || true

invoke_claude() {
  local ws="$1" prompt_file="$2" evdir="$3" tag="$4"; shift 4
  mkdir -p "${evdir}"
  local stream="${evdir}/${tag}.stream-json.jsonl"
  local debug="${evdir}/${tag}.debug.log"
  local started ended elapsed=0
  started="$(date +%s)"
  echo "invoke: claude (${tag}): $(head -c 120 "${prompt_file}" | tr '\n' ' ')..."

  # Pre-approve EXACTLY the installed generator (bare and --check forms,
  # relative paths only). --settings merges with project settings, so fixture
  # denies still apply (verified by probe). Anything else the model tries
  # still prompts, which in -p mode ends the turn for an honest failure.
  local generator_allow='{"permissions":{"allow":["Bash(agent/tools/loom.sh)","Bash(agent/tools/loom.sh *)","Bash(./agent/tools/loom.sh)","Bash(./agent/tools/loom.sh *)"]}}'
  local -a cmd
  cmd=(claude -p --output-format stream-json --verbose
    --include-partial-messages
    --setting-sources "user,project,local"
    --settings "${generator_allow}"
    --add-dir "${ws}" --session-id "$(cat /proc/sys/kernel/random/uuid)"
    --debug-file "${debug}")
  [[ -n "${E2E_TIMEOUT:-}" ]] && cmd=(timeout "${E2E_TIMEOUT}" "${cmd[@]}")

  set +e
  (cd "${ws}" && run_isolated "${cmd[@]}" "$@" "$(cat "${prompt_file}")") \
    > "${stream}.tmp" 2>"${evdir}/${tag}.stderr.log"
  INVOKE_EXIT=$?
  set -e
  mv "${stream}.tmp" "${stream}"
  ended="$(date +%s)"
  elapsed=$(( (ended - started) * 1000 ))

  # Consumption from the stream (tokens/cost when the harness reports them).
  local in_tok out_tok cost model
  in_tok="$(jq -s '[.. | objects | .input_tokens? // empty] | add // 0' "${stream}" 2>/dev/null || echo 0)"
  out_tok="$(jq -s '[.. | objects | .output_tokens? // empty] | add // 0' "${stream}" 2>/dev/null || echo 0)"
  cost="$(jq -s -r '[.. | objects | .total_cost_usd? // .cost_usd? // empty] | last // empty' "${stream}" 2>/dev/null || true)"
  model="$(jq -s -r '[.. | objects | .model? // empty] | last // empty' "${stream}" 2>/dev/null || true)"
  [[ "${in_tok}" == "null" || -z "${in_tok}" ]] && in_tok=0
  [[ "${out_tok}" == "null" || -z "${out_tok}" ]] && out_tok=0
  local ceiling_json="null"
  [[ -n "${E2E_CEILING_USD:-}" ]] && ceiling_json="{\"usd\": ${E2E_CEILING_USD}}"
  jq -n --argjson elapsed "${elapsed}" \
    --argjson it "${in_tok:-0}" --argjson ot "${out_tok:-0}" \
    --arg cost "${cost}" --arg model "${model}" \
    --argjson ceiling "${ceiling_json}" \
    --argjson timeout "${E2E_TIMEOUT:-null}" '{
      elapsed_ms: $elapsed,
      input_tokens: (if $it == null then null else $it end),
      output_tokens: (if $ot == null then null else $ot end),
      cost_usd: (if $cost == "" then null else ($cost | tonumber? // $cost) end),
      model: (if $model == "" then null else $model end),
      ceiling: $ceiling, timeout_s: $timeout
    }' > "${evdir}/${tag}.consumption.json"
  echo "invoke: ${tag} exit=${INVOKE_EXIT} elapsed=$((elapsed / 1000))s in=${in_tok} out=${out_tok} cost=${cost:-unknown}"
  if [[ -n "${E2E_CEILING_USD:-}" && -n "${cost}" && "${cost}" != "null" ]]; then
    if python3 -c "exit(0 if float('${cost}') <= float('${E2E_CEILING_USD}') else 1)" 2>/dev/null; then
      :
    else
      echo "live: ${tag} exceeded opt-in ceiling USD ${E2E_CEILING_USD} (spent ${cost})"
      INVOKE_EXIT=99
    fi
  fi
  return 0
}

# invoke_auth_failed <evidence-dir> <tag> -> 0 + reason when the invocation
# failed because credentials are absent/expired (Pr. VIII: reported blocked
# with the missing prerequisite named, never failed) (T107).
invoke_auth_failed() {
  local evdir="$1" tag="$2" reason=""
  if [[ "${INVOKE_EXIT}" -eq 0 ]]; then return 1; fi
  if grep -Eq -i 'oauth refresh token is no longer valid|refresh token.*expired|failed to authenticate|authentication_failed|invalid.*api key|re-authenticate' \
    "${evdir}/${tag}.stderr.log" "${evdir}/${tag}.stream-json.jsonl" 2>/dev/null; then
    reason="claude credentials rejected (OAuth refresh token expired or API key invalid — run claude /login and re-run this suite)"
    echo "${reason}" >&2
    return 0
  fi
  return 1
}
