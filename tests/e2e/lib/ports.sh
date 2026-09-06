#!/usr/bin/env bash
# lib/ports.sh — collision-safe port allocation (T013).
#
#   alloc_port <name>
# Binds port 0 to find a free port, records {name: port} in
# $E2E_RUN_DIR/ports.json (merged into resolved-input.json when the suite
# freezes inputs), and prints the port. Uniqueness across concurrent runs
# comes from the kernel allocator, not from a shared counter.
: "${E2E_RUN_DIR:?}"

alloc_port() {
  local name="$1" port
  port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
  [[ -n "${port}" ]] || { echo "alloc_port: kernel gave no port" >&2; return 1; }
  local pf="${E2E_RUN_DIR}/ports.json"
  [[ -f "${pf}" ]] || echo '{}' > "${pf}"
  jq --arg k "${name}" --argjson v "${port}" '.[$k] = $v' "${pf}" > "${pf}.tmp" \
    && mv "${pf}.tmp" "${pf}"
  if [[ -n "${E2E_WORKSPACE:-}" && -f "${E2E_WORKSPACE}/workspace.json" ]]; then
    jq --arg k "${name}" --argjson v "${port}" '.ports[$k] = $v' \
      "${E2E_WORKSPACE}/workspace.json" > "${E2E_WORKSPACE}/workspace.json.tmp" \
      && mv "${E2E_WORKSPACE}/workspace.json.tmp" "${E2E_WORKSPACE}/workspace.json"
  fi
  echo "${port}"
}
