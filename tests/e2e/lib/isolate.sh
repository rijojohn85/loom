#!/usr/bin/env bash
# lib/isolate.sh — per-run harness sandboxing (T011, research D11).
#
#   isolate_env
# Points HOME, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_CACHE_HOME, CODEX_HOME and
# CLAUDE_CONFIG_DIR at <run-dir>/home/ (repo-local, git-ignored — never /tmp,
# because Codex refuses helper binaries under a temporary directory), records
# the mapping into workspace.json, and exports everything.
#
#   run_isolated <cmd...>
# Runs a harness child with `env -i`: only the sandbox paths, a minimal PATH,
# TERM, and the named credential variables (ANTHROPIC_API_KEY, OPENAI_API_KEY).
# Every other variable is scrubbed.
: "${E2E_RUN_DIR:?}"

# Tool directories resolved once, while the ambient PATH is intact, so
# isolated children can still find the harness CLIs without inheriting
# developer state through PATH.
_E2E_TOOL_DIRS=""
for _t in claude codex opencode git jq python3 bash; do
  _p="$(command -v "${_t}" 2>/dev/null || true)"
  [[ -n "${_p}" ]] || continue
  _d="$(dirname "${_p}")"
  case "${_E2E_TOOL_DIRS}" in
    *"${_d}"*) ;;
    *) _E2E_TOOL_DIRS="${_E2E_TOOL_DIRS}:${_d}" ;;
  esac
done
_E2E_TOOL_PATH="/usr/local/bin:/usr/bin:/bin${_E2E_TOOL_DIRS}"
unset _t _p _d

isolate_env() {
  : "${E2E_WORKSPACE:?isolate_env needs E2E_WORKSPACE}"
  local home="${E2E_RUN_DIR}/home"
  mkdir -p "${home}/config" "${home}/data" "${home}/cache" \
           "${home}/codex" "${home}/claude"
  export HOME="${home}"
  export XDG_CONFIG_HOME="${home}/config"
  export XDG_DATA_HOME="${home}/data"
  export XDG_CACHE_HOME="${home}/cache"
  export CODEX_HOME="${home}/codex"
  export CLAUDE_CONFIG_DIR="${home}/claude"
  # shellcheck disable=SC1091
  source "${E2E_ROOT}/lib/workspace.sh" 2>/dev/null || true
  workspace_update \
    --arg home "${home}" --arg cfg "${home}/config" \
    --arg data "${home}/data" --arg cache "${home}/cache" \
    --arg codex "${home}/codex" --arg claude "${home}/claude" \
    '.isolation_env = {HOME: $home, XDG_CONFIG_HOME: $cfg,
      XDG_DATA_HOME: $data, XDG_CACHE_HOME: $cache,
      CODEX_HOME: $codex, CLAUDE_CONFIG_DIR: $claude}'
}

run_isolated() {  # <cmd...>
  local -a _env=("HOME=${HOME}" "XDG_CONFIG_HOME=${XDG_CONFIG_HOME}"
    "XDG_DATA_HOME=${XDG_DATA_HOME}" "XDG_CACHE_HOME=${XDG_CACHE_HOME}"
    "CODEX_HOME=${CODEX_HOME}" "CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR}"
    "PATH=${_E2E_TOOL_PATH}" "TERM=${TERM:-xterm}")
  [[ -n "${ANTHROPIC_API_KEY:-}" ]] && \
    _env+=("ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}")
  [[ -n "${OPENAI_API_KEY:-}" ]] && \
    _env+=("OPENAI_API_KEY=${OPENAI_API_KEY}")
  env -i "${_env[@]}" "$@"
}

inject_claude_credentials() {  # <real-home> — copy ONLY the OAuth file
  # The login lives in the real home, which isolation hides. Copying the
  # single credentials file is injecting the credential this scenario
  # requires — never the whole home directory or credential store.
  local real_home="$1"
  if [[ -z "${ANTHROPIC_API_KEY:-}" ]] \
    && [[ -f "${real_home}/.claude/.credentials.json" ]]; then
    cp "${real_home}/.claude/.credentials.json" \
      "${CLAUDE_CONFIG_DIR:?}/.credentials.json"
    chmod 600 "${CLAUDE_CONFIG_DIR}/.credentials.json"
    echo "isolate: injected claude OAuth credentials into per-run config (file only)"
  fi
}
