#!/usr/bin/env bash
# suites/offline/portability.sh — generate in two separate workspaces and
# assert no absolute temporary path or machine-local value differs,
# normalising only declared ephemeral fields (T042, FR-039).
set -euo pipefail
E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${E2E_RUN_DIR:?}" "${E2E_WORKSPACE:?}" "${E2E_OFFLINE_DIR:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/workspace.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/install.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/offline/materialize.sh"

# Second workspace from the same frozen inputs: reuse the base resolved-input
# ports/URLs so bytes must match after ephemeral normalisation.
make_workspace "${E2E_ROOT}/fixtures/complete-claude"
WS2="${E2E_WORKSPACE}"
install_loom "${WS2}" "${E2E_OFFLINE_DIR}/portability-install.log" >/dev/null 2>&1
# Force identical inputs: copy the frozen resolved-input and materialize with it.
cp "${E2E_OFFLINE_DIR}/base/resolved-input.json" "${E2E_OFFLINE_DIR}/port-ws2-resolved.json"
url_a="$(jq -r .mcp_urls.docs_a "${E2E_OFFLINE_DIR}/base/resolved-input.json")"
url_b="$(jq -r .mcp_urls.docs_b "${E2E_OFFLINE_DIR}/base/resolved-input.json")"
sed -i "s|{{MCP_HTTP_URL_A}}|${url_a}|g; s|{{MCP_HTTP_URL_B}}|${url_b}|g" \
  "${WS2}/.mcp.json" "${WS2}/agent/policies/allowed-mcp-servers.md"
jq '.paths.mcp_allowlist = "agent/policies/allowed-mcp-servers.md" | .mcp_note = "Read-only docs servers."' \
  "${WS2}/agent/tools/loom.config.json" > "${WS2}/agent/tools/loom.config.json.tmp" \
  && mv "${WS2}/agent/tools/loom.config.json.tmp" "${WS2}/agent/tools/loom.config.json"
(cd "${WS2}" && ./agent/tools/loom.sh >/dev/null 2>&1)

WS1="$(cat "${E2E_OFFLINE_DIR}/base/workspace-path.txt")"
reason=""
for rel in .codex/config.toml opencode.json .devin/mcp_config.json .devin/config.json .devin/hooks.v1.json agent/harness-specs/GAPS.md; do
  if ! "${E2E_ROOT}/tools/compare.py" "${WS1}/${rel}" "${WS2}/${rel}" \
      --resolved-input "${E2E_OFFLINE_DIR}/base/resolved-input.json" \
      >"${E2E_OFFLINE_DIR}/portability-${rel//\//_}.diff" 2>&1; then
    reason="cross-workspace difference beyond ephemeral fields: ${rel}"
    break
  fi
done
# Absolute temporary paths must not leak into any generated artifact.
if [[ -z "${reason}" ]]; then
  if grep -r "/tmp/loom-e2e-" "${WS2}/.codex" "${WS2}/.devin" "${WS2}/opencode.json" \
      "${WS2}/agent/harness-specs/GAPS.md" 2>/dev/null; then
    reason="absolute temporary path leaked into generated artifacts"
  fi
fi

export E2E_WORKSPACE="${WS1}"
if [[ -z "${reason}" ]]; then
  record_check id=offline.portability suite=offline mandatory=true state=passed \
    claim_kind=local-structural
else
  record_check id=offline.portability suite=offline mandatory=true state=failed \
    reason="${reason}" claim_kind=local-structural
fi
