#!/usr/bin/env bash
# suites/offline/materialize.sh — fixture -> workspace materialization.
# Sourced by suite drivers (offline, mutation). Not a check itself.
#
#   materialize_variant <variant> <workspace> <state-dir>
# Copies the variant overlay over the workspace, allocates fixture ports,
# substitutes {{MCP_HTTP_URL_A/B}} in .mcp.json and the allowlist, configures
# the installed loom.config.json (allowlist path, note, variant patch), and
# freezes <state-dir>/resolved-input.json.
: "${E2E_ROOT:?}" "${REPO_ROOT:?}"

materialize_variant() {
  local variant="$1" ws="$2" statedir="$3"
  local vdir="${E2E_ROOT}/fixtures/variants/${variant}"
  mkdir -p "${statedir}"

  if [[ "${variant}" != "base" ]]; then
    [[ -d "${vdir}" ]] || { echo "materialize: unknown variant ${variant}" >&2; return 2; }
    (cd "${vdir}" && find . -type f ! -name manifest.json -print0) | while IFS= read -r -d '' f; do
      mkdir -p "${ws}/$(dirname "${f}")"
      cp "${vdir}/${f}" "${ws}/${f}"
    done
  fi

  # shellcheck disable=SC1091
  source "${E2E_ROOT}/lib/ports.sh"
  local port_a port_b
  port_a="$(alloc_port "mcp_a_${variant}")"
  port_b="$(alloc_port "mcp_b_${variant}")"
  local url_a="http://127.0.0.1:${port_a}/mcp" url_b="http://127.0.0.1:${port_b}/mcp"

  sed -i "s|{{MCP_HTTP_URL_A}}|${url_a}|g; s|{{MCP_HTTP_URL_B}}|${url_b}|g" \
    "${ws}/.mcp.json" "${ws}/agent/policies/allowed-mcp-servers.md" 2>/dev/null || true
  # Any leftover placeholder after substitution is a materialization bug.
  if grep -r "{{MCP_HTTP_URL_" "${ws}/.mcp.json" "${ws}/agent/policies/allowed-mcp-servers.md" 2>/dev/null; then
    echo "materialize: unsubstituted placeholder remains" >&2; return 1
  fi
  # Self-contained stdio service: the fixture's repo-relative server path
  # would not resolve from /tmp, so copy the service in and point at the copy.
  # The audit-log arg is REQUIRED (mcp_stdio.py fails fast without it, T108);
  # the path stays workspace-relative so no machine-local value reaches
  # generated artifacts.
  if jq -e '.mcpServers["docs-local"]' "${ws}/.mcp.json" >/dev/null 2>&1; then
    mkdir -p "${ws}/services"
    cp "${E2E_ROOT}/fixtures/services/mcp_stdio.py" "${ws}/services/mcp_stdio.py"
    jq '.mcpServers["docs-local"].args = ["-u", "services/mcp_stdio.py", "services/stdio-audit.log"]' \
      "${ws}/.mcp.json" > "${ws}/.mcp.json.tmp" \
      && mv "${ws}/.mcp.json.tmp" "${ws}/.mcp.json"
  fi

  local cfg="${ws}/agent/tools/loom.config.json"
  jq '.paths.mcp_allowlist = "agent/policies/allowed-mcp-servers.md"
      | .mcp_note = "Read-only docs servers."' "${cfg}" > "${cfg}.tmp" \
    && mv "${cfg}.tmp" "${cfg}"
  if [[ "${variant}" != "base" ]]; then
    local patch
    patch="$(jq -c '.loom_config_patch // empty' "${vdir}/manifest.json")"
    if [[ -n "${patch}" ]]; then
      patch="${patch//\{\{url\}\}/${url_b}}"
      jq --argjson p "${patch}" '. * $p' "${cfg}" > "${cfg}.tmp" \
        && mv "${cfg}.tmp" "${cfg}"
    fi
  fi

  local servers
  servers="$(jq -r '.mcpServers | keys[]' "${ws}/.mcp.json" 2>/dev/null | head -20 || true)"
  jq -n --arg variant "${variant}" \
    --argjson pa "${port_a}" --argjson pb "${port_b}" \
    --arg ua "${url_a}" --arg ub "${url_b}" \
    --arg fixture_rev "$("${E2E_ROOT}/tools/digest.py" "${E2E_ROOT}/fixtures")" \
    --arg cfg_digest "$("${E2E_ROOT}/tools/digest.py" "${cfg}")" \
    --arg ws "${ws}" '{
      variant: $variant, workspace: $ws,
      fixture_revision: $fixture_rev, loom_config_digest: $cfg_digest,
      ports: {mcp_a: $pa, mcp_b: $pb},
      mcp_urls: {docs_a: $ua, docs_b: $ub},
      ephemeral_fields: {mcp_port_a: ($pa | tostring), mcp_url_a: $ua,
                         mcp_port_b: ($pb | tostring), mcp_url_b: $ub}
    }' > "${statedir}/resolved-input.json"
  cp "${statedir}/resolved-input.json" "${ws}/resolved-input.json"
  echo "${servers}" > "${statedir}/servers.txt"
}
