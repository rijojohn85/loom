#!/usr/bin/env bash
# lib/trust.sh — seed project trust into the per-run config only (T012, D11).
#
#   seed_trust <workspace> <server> [...]
# Codex: [projects."<ws>"] trust_level = "trusted" in $CODEX_HOME/config.toml
# Claude: projects["<ws>"] = {hasTrustDialogAccepted, enabledMcpjsonServers,
#   hasClaudeMdExternalIncludesApproved} in $CLAUDE_CONFIG_DIR/.claude.json
# opencode: no gate — recorded as an observed fact.
# Refuses to write anywhere outside the run directory. Records what was
# seeded into workspace.json. With E2E_NO_TRUST_SEED=1, seeds nothing and
# records seeded:false (the untrusted-canary negative check).
: "${E2E_RUN_DIR:?}"

seed_trust() {
  : "${E2E_WORKSPACE:?seed_trust needs E2E_WORKSPACE}"
  local ws="$1"; shift
  local servers=("$@")
  local servers_json
  servers_json="$(printf '%s\n' "${servers[@]}" | jq -R . | jq -s .)"
  local codex_cfg="${CODEX_HOME:?CODEX_HOME unset}/config.toml"
  local claude_json="${CLAUDE_CONFIG_DIR:?CLAUDE_CONFIG_DIR unset}/.claude.json"

  case "${codex_cfg} ${claude_json}" in
    "${E2E_RUN_DIR}"/*) ;;
    *) echo "seed_trust: refusing to write outside run dir" >&2; return 2 ;;
  esac

  if [[ "${E2E_NO_TRUST_SEED:-0}" == "1" ]]; then
    workspace_update '.trust_seeded = {codex: {seeded: false},
      claude: {seeded: false}, opencode: {seeded: false, note: "no gate observed"}}'
    return 0
  fi

  mkdir -p "$(dirname "${codex_cfg}")" "$(dirname "${claude_json}")"
  if [[ -f "${codex_cfg}" ]] && ! grep -qF "[projects.\"${ws}\"]" "${codex_cfg}"; then
    cat >> "${codex_cfg}" <<TOML

[projects."${ws}"]
trust_level = "trusted"
TOML
  elif [[ ! -f "${codex_cfg}" ]]; then
    cat > "${codex_cfg}" <<TOML
[projects."${ws}"]
trust_level = "trusted"
TOML
  fi

  if [[ -f "${claude_json}" ]]; then
    jq --arg ws "${ws}" --argjson srv "${servers_json}" \
      '.projects[$ws] = {hasTrustDialogAccepted: true,
        enabledMcpjsonServers: $srv, hasClaudeMdExternalIncludesApproved: true}' \
      "${claude_json}" > "${claude_json}.tmp" && mv "${claude_json}.tmp" "${claude_json}"
  else
    jq -n --arg ws "${ws}" --argjson srv "${servers_json}" \
      '{projects: {($ws): {hasTrustDialogAccepted: true,
        enabledMcpjsonServers: $srv, hasClaudeMdExternalIncludesApproved: true}}}' \
      > "${claude_json}"
  fi

  workspace_update --arg ws "${ws}" --arg codex "${codex_cfg}" \
    --arg claude "${claude_json}" --argjson srv "${servers_json}" \
    '.trust_seeded = {codex: {seeded: true, mechanism: "trust_level=trusted",
      path: $codex, approved_mcp_servers: $srv},
      claude: {seeded: true,
        mechanism: "hasTrustDialogAccepted+enabledMcpjsonServers+hasClaudeMdExternalIncludesApproved",
        path: $claude, approved_mcp_servers: $srv},
      opencode: {seeded: false, note: "no gate observed"}}'
}
