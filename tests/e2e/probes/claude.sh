#!/usr/bin/env bash
# probes/claude.sh — Claude Code 2.1.263 source-baseline probe (T073).
# Functions take a workspace path as $1 and print one JSON payload.
# shellcheck disable=SC1091
source "${E2E_ROOT}/probes/_adapter.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/isolate.sh" 2>/dev/null || true

_claude_ver() { probe_cli_version claude; }

probe_available() {
  local v
  v="$(_claude_ver)"
  if [[ -n "${v}" ]]; then
    probe_emit claude "${v}" "claude --version" ok "" "{\"version\": \"${v}\"}"
  else
    probe_emit claude "" "claude --version" blocked "claude CLI absent" '{}'
  fi
}

probe_version() {
  local v pinned
  v="$(_claude_ver)"
  pinned="$(jq -r '.harnesses.claude.version // empty' "${E2E_ROOT}/pins/harnesses.json")"
  if [[ -z "${v}" ]]; then
    probe_emit claude "" "claude --version" blocked "claude CLI absent" '{}'
  elif [[ "${v}" == "${pinned}" ]]; then
    probe_emit claude "${v}" "claude --version" ok "" "{\"pinned\": \"${pinned}\"}"
  else
    probe_emit claude "${v}" "claude --version" failed \
      "version mismatch: observed ${v}, pinned ${pinned}" "{\"pinned\": \"${pinned}\"}"
  fi
}

probe_isolated() {  # CLAUDE_CONFIG_DIR self-check (verified mechanism, D11)
  local ws="$1" v
  v="$(_claude_ver)"
  [[ -n "${v}" ]] || { probe_emit claude "" "CLAUDE_CONFIG_DIR self-check" blocked "claude CLI absent" '{}'; return; }
  case "${CLAUDE_CONFIG_DIR:-}" in
    "${E2E_RUN_DIR:-__unset__}"/*)
      [[ -f "${CLAUDE_CONFIG_DIR}/.claude.json" ]] \
        && probe_emit claude "${v}" "CLAUDE_CONFIG_DIR self-check" ok \
             "per-run .claude.json present; developer config untouched" '{}' \
        || probe_emit claude "${v}" "CLAUDE_CONFIG_DIR self-check" failed \
             "per-run .claude.json absent (seed trust first)" '{}' ;;
    *) probe_emit claude "${v}" "CLAUDE_CONFIG_DIR self-check" failed \
         "CLAUDE_CONFIG_DIR (${CLAUDE_CONFIG_DIR:-unset}) escapes the run directory" '{}' ;;
  esac
}

seed_trust() {
  local ws="$1"; shift
  # shellcheck disable=SC1091
  source "${E2E_ROOT}/lib/trust.sh" 2>/dev/null || true
  local v
  v="$(_claude_ver)"
  if seed_trust "${ws}" "$@"; then
    probe_emit claude "${v}" "trust-seed into \$CLAUDE_CONFIG_DIR/.claude.json" ok "" \
      "{\"workspace\": \"${ws}\"}"
  else
    probe_emit claude "${v}" "trust-seed into \$CLAUDE_CONFIG_DIR/.claude.json" failed \
      "seed_trust refused or failed" '{}'
  fi
}

probe_trust_state() {  # server approval states as reported by the CLI
  local ws="$1" v out
  v="$(_claude_ver)"
  [[ -n "${v}" ]] || { probe_emit claude "" "claude mcp list" blocked "claude CLI absent" '{}'; return; }
  if out="$(cd "${ws}" && run_isolated claude mcp list 2>&1)"; then
    if grep -q "Pending approval" <<<"${out}"; then
      probe_emit claude "${v}" "claude mcp list" ok "servers pending approval (untrusted)" \
        "$(jq -c -R -s '{raw: .[0:400]}' <<<"${out}")"
    else
      probe_emit claude "${v}" "claude mcp list" ok "servers listed without pending approval" \
        "$(jq -c -R -s '{raw: .[0:400]}' <<<"${out}")"
    fi
  else
    probe_emit claude "${v}" "claude mcp list" failed "mcp list failed" '{}'
  fi
}

probe_loaded_config() {
  local ws="$1" v out
  v="$(_claude_ver)"
  [[ -n "${v}" ]] || { probe_emit claude "" "claude mcp list" blocked "claude CLI absent" '{}'; return; }
  if out="$(cd "${ws}" && run_isolated claude mcp list 2>/dev/null)"; then
    probe_emit claude "${v}" "claude mcp list" ok "" \
      "$(jq -c -R -s '{raw: .[0:400]}' <<<"${out}")"
  else
    probe_emit claude "${v}" "claude mcp list" failed "mcp list failed" '{}'
  fi
}

probe_unknown_field() {
  local v
  v="$(_claude_ver)"
  probe_emit claude "${v}" "none" blocked \
    "no verified unknown-field rejection interface for Claude settings" '{}'
}

probe_mcp_list() { probe_loaded_config "$1"; }

# _claude_auth_failed <text> -> 0 when the run was rejected on credentials
# (Pr. VIII: rejected credentials report blocked, never passed or failed).
_claude_auth_failed() {
  grep -Eqi 'refresh token is no longer valid|failed to authenticate|re-authenticate|not logged in|unauthorized|invalid.*api key' <<<"$1"
}

probe_mcp_call() {  # permitted docs call through the source harness (credentialed)
  local ws="$1" v out code
  v="$(_claude_ver)"
  [[ -n "${v}" ]] || { probe_emit claude "" "claude -p --output-format stream-json" blocked "claude CLI absent" '{}'; return; }
  [[ "${E2E_HAVE_CREDS:-0}" == "1" ]] \
    || { probe_emit claude "${v}" "claude -p --output-format stream-json" blocked \
           "no live credentials" '{}'; return; }
  set +e
  out="$(cd "${ws}" && run_isolated claude -p --output-format stream-json --verbose \
    --setting-sources user,project,local \
    "Call the docs-a MCP server docs.list tool and report its exact output" \
    < /dev/null 2>&1)"
  code=$?
  set -e
  mkdir -p "${E2E_RUN_DIR}/conformance/transcripts" 2>/dev/null || true
  printf '%s' "${out}" > "${E2E_RUN_DIR}/conformance/transcripts/claude-mcp-call.log" 2>/dev/null || true
  if _claude_auth_failed "${out}"; then
    probe_emit claude "${v}" "claude -p --output-format stream-json" blocked \
      "no usable live credentials (OAuth token expired or invalid — run claude /login)" '{}'
  elif [[ "${code}" -eq 0 ]] && grep -Eq "docs[._-]list" <<<"${out}" \
    && grep -q "api,readme" <<<"${out}"; then
    probe_emit claude "${v}" "claude -p --output-format stream-json" ok \
      "permitted MCP call returned fixture content" '{}'
  elif [[ "${code}" -eq 0 ]]; then
    probe_emit claude "${v}" "claude -p --output-format stream-json" failed \
      "MCP call answered without fixture content" '{}'
  else
    probe_emit claude "${v}" "claude -p --output-format stream-json" failed \
      "call failed (exit ${code})" '{}'
  fi
}

probe_context_loaded() {  # source baseline expression (credentialed)
  local ws="$1" v out code
  v="$(_claude_ver)"
  [[ -n "${v}" ]] || { probe_emit claude "" "claude -p --output-format stream-json" blocked "claude CLI absent" '{}'; return; }
  [[ "${E2E_HAVE_CREDS:-0}" == "1" ]] \
    || { probe_emit claude "${v}" "claude -p --output-format stream-json" blocked \
           "no live credentials" '{}'; return; }
  set +e
  # Indirect: answerable from auto-loaded project context only. Naming the
  # file would let --safe-mode runs read it explicitly, voiding the control.
  out="$(cd "${ws}" && run_isolated claude -p --output-format stream-json --verbose \
    --setting-sources user,project,local \
    "What project-specific rules govern how you make edits here? Cite the exact rule text." \
    < /dev/null 2>&1)"
  code=$?
  set -e
  # Paraphrase-tolerant canary: the rule's distinctive elements (deny +
  # gap/reviewed) rather than the exact sentence.
  if [[ "${code}" -eq 0 ]] && grep -qi "deny" <<<"${out}" \
    && grep -Eqi "gap|reviewed" <<<"${out}"; then
    probe_emit claude "${v}" "claude -p --output-format stream-json" ok \
      "baseline expresses the intended context" '{}'
  elif _claude_auth_failed "${out}"; then
    probe_emit claude "${v}" "claude -p --output-format stream-json" blocked \
      "no usable live credentials" '{}'
  else
    probe_emit claude "${v}" "claude -p --output-format stream-json" failed \
      "baseline did not express the intended context (exit ${code})" '{}'
  fi
}

probe_permission() {  # approval-required probe (credentialed)
  local ws="$1" v out code
  v="$(_claude_ver)"
  [[ -n "${v}" ]] || { probe_emit claude "" "claude -p --permission-prompts none" blocked "claude CLI absent" '{}'; return; }
  [[ "${E2E_HAVE_CREDS:-0}" == "1" ]] \
    || { probe_emit claude "${v}" "claude -p --permission-prompts none" blocked \
           "no live credentials" '{}'; return; }
  set +e
  out="$(cd "${ws}" && run_isolated claude -p --output-format stream-json --verbose \
    --setting-sources user,project,local --permission-prompts none \
    "Push the current branch to origin with git push" < /dev/null 2>&1)"
  code=$?
  set -e
  if _claude_auth_failed "${out}"; then
    probe_emit claude "${v}" "claude -p --permission-prompts none" blocked \
      "no usable live credentials" '{}'
  elif grep -qi "denied\|permission\|ask\|approval\|cannot\|won't\|refus" <<<"${out}"; then
    probe_emit claude "${v}" "claude -p --permission-prompts none" ok \
      "approval-required action did not execute unapproved" '{}'
  elif [[ -f "${ws}/.git-pushed-canary" ]]; then
    probe_emit claude "${v}" "claude -p --permission-prompts none" failed \
      "forbidden side effect observed" '{}'
  else
    probe_emit claude "${v}" "claude -p --permission-prompts none" failed \
      "no refusal signal in output (exit ${code})" '{}'
  fi
}

probe_hook_audit() {  # the fixture audit log, read — never written — here
  local ws="$1" v
  v="$(_claude_ver)"
  if [[ -f "${ws}/hooks/audit.log" ]]; then
    probe_emit claude "${v}" "fixture hooks/audit.log" ok "" \
      "$(jq -R -s --arg n "$(wc -l < "${ws}/hooks/audit.log")" \
        '{entries: $n}' <<<'' 2>/dev/null || echo '{}')"
  else
    probe_emit claude "${v}" "fixture hooks/audit.log" blocked \
      "no hook activity recorded in this workspace yet" '{}'
  fi
}

probe_native_assets() {  # source harness trivially carries its own assets
  local ws="$1" v skills agents
  v="$(_claude_ver)"
  skills="$(find "${ws}/.claude/skills" -name SKILL.md 2>/dev/null | wc -l)"
  agents="$(find "${ws}/.claude/agents" -name '*.md' 2>/dev/null | wc -l)"
  probe_emit claude "${v}" "workspace asset listing" ok "" \
    "{\"skills\": ${skills}, \"agents\": ${agents}}"
}
