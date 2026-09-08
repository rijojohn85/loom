#!/usr/bin/env bash
# lib/workspace.sh — temp repo creation, fixture copy, cleanup (T010, T036).
#
#   make_workspace <fixture-dir>
# Creates /tmp/loom-e2e-<timestamp>-<pid>-<n> with collision-safe suffixing,
# copies the fixture preserving dotfiles and executable bits, runs git init,
# refuses any symlink back to the checkout, records workspace.json, appends
# the path to $E2E_RUN_DIR/workspaces.lst and exports E2E_WORKSPACE.
#
# T036: a trap on EXIT/INT/TERM terminates fixture services, harness child
# processes and any orphaned process group the run started. Suites register
# PIDs with register_child_pid; assert_no_survivors verifies nothing survives.
: "${E2E_RUN_DIR:?}" "${E2E_ROOT:?}" "${REPO_ROOT:?}"

workspace_update() {  # [jq options...] <jq-program> — merge into workspace.json
  local ws="${E2E_WORKSPACE:?}"
  local -a _wu_args=( "$@" )
  local prog="${_wu_args[${#_wu_args[@]}-1]}"
  set -- "${@:1:$#-1}"
  jq "$@" "${prog}" "${ws}/workspace.json" > "${ws}/workspace.json.tmp" \
    && mv "${ws}/workspace.json.tmp" "${ws}/workspace.json"
}

register_child_pid() {  # <pid> [...]
  local p
  for p in "$@"; do echo "${p}" >> "${E2E_RUN_DIR}/child-pids.lst"; done
  touch "${E2E_RUN_DIR}/child-pids.lst"
}

assert_no_survivors() {  # echoes survivors; returns 1 if any run-started PID lives
  local bad=0 p
  touch "${E2E_RUN_DIR}/child-pids.lst"
  while IFS= read -r p; do
    [[ -n "${p}" ]] || continue
    if kill -0 "${p}" 2>/dev/null; then echo "survivor: ${p}"; bad=1; fi
  done < "${E2E_RUN_DIR}/child-pids.lst"
  return "${bad}"
}

_e2e_cleanup_children() {
  local p
  [[ -f "${E2E_RUN_DIR:-}/child-pids.lst" ]] || return 0
  while IFS= read -r p; do
    [[ -n "${p}" ]] || continue
    kill -TERM "-${p}" 2>/dev/null || kill -TERM "${p}" 2>/dev/null || true
  done < "${E2E_RUN_DIR}/child-pids.lst"
  sleep 1
  while IFS= read -r p; do
    [[ -n "${p}" ]] || continue
    kill -KILL "-${p}" 2>/dev/null || kill -KILL "${p}" 2>/dev/null || true
  done < "${E2E_RUN_DIR}/child-pids.lst"
}
trap _e2e_cleanup_children EXIT INT TERM

make_workspace() {  # <fixture-dir>
  local fixture="$1" n=0 ws stamp
  [[ -d "${fixture}" ]] || { echo "make_workspace: no fixture ${fixture}" >&2; return 2; }
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  while :; do
    ws="/tmp/loom-e2e-${stamp}-$$-${n}"
    [[ -e "${ws}" ]] || break
    n=$((n + 1))
  done
  mkdir -p "${ws}"
  cp -a "${fixture}/." "${ws}/"
  if [[ -e "${ws}/.git" ]]; then
    echo "make_workspace: fixture carries .git — refusing" >&2; return 2
  fi
  # Refuse any symlink pointing back at the checkout.
  local link target
  while IFS= read -r -d '' link; do
    target="$(readlink "${link}")"
    case "${target}" in "${REPO_ROOT}"*|"${E2E_ROOT}"*)
      echo "make_workspace: symlink escapes to checkout: ${link}" >&2; return 2 ;;
    esac
  done < <(find "${ws}" -type l -print0)
  git -C "${ws}" init -q .
  git -C "${ws}" config user.email "loom-e2e@example.invalid"
  git -C "${ws}" config user.name "loom-e2e"
  cat > "${ws}/workspace.json" <<JSON
{"path": "${ws}", "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
 "ports": {}, "kept": false,
 "git_revision": "$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)",
 "isolation_env": {}, "oracle_digest_before": null,
 "oracle_digest_after": null, "trust_seeded": {}}
JSON
  echo "${ws}" >> "${E2E_RUN_DIR}/workspaces.lst"
  export E2E_WORKSPACE="${ws}"
}
