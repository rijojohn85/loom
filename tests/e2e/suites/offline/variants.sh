#!/usr/bin/env bash
# suites/offline/variants.sh — every selected variant is generated and
# validated, with per-variant results recorded (T047).
set -euo pipefail
E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${E2E_RUN_DIR:?}" "${E2E_OFFLINE_DIR:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"

IFS=',' read -ra VARIANTS <<< "${E2E_VARIANTS:-base}"
for variant in "${VARIANTS[@]}"; do
  vdir="${E2E_OFFLINE_DIR}/${variant}"
  cid="offline.variant.${variant}"
  if [[ ! -f "${vdir}/generate-ok.txt" ]]; then
    record_check id="${cid}" suite=offline mandatory=true state=failed \
      reason="variant ${variant} was never materialized" claim_kind=none
    continue
  fi
  gen_ok="$(cat "${vdir}/generate-ok.txt")"
  ws="$(cat "${vdir}/workspace-path.txt" 2>/dev/null || echo "")"
  if [[ "${variant}" == "base" ]]; then
    if [[ "${gen_ok}" == "1" ]]; then
      record_check id="${cid}" suite=offline mandatory=true state=passed \
        claim_kind=local-structural
    else
      record_check id="${cid}" suite=offline mandatory=true state=failed \
        reason="base generation failed: $(head -1 "${vdir}/generate.log")" \
        claim_kind=local-structural
    fi
    continue
  fi
  manifest="${E2E_ROOT}/fixtures/variants/${variant}/manifest.json"
  expected="$(jq -r .expected_generation "${manifest}")"
  if [[ "${expected}" == "refuse" ]]; then
    pattern="$(jq -r .expected_reason_pattern "${manifest}")"
    log="$(cat "${vdir}/generate.log" 2>/dev/null || true)"
    if [[ "${gen_ok}" == "0" ]] && grep -Eq "${pattern}" <<<"${log}"; then
      record_check id="${cid}" suite=offline mandatory=true state=passed \
        claim_kind=behaviour-probe interface="agent/tools/loom.sh"
    elif [[ "${gen_ok}" == "1" ]]; then
      record_check id="${cid}" suite=offline mandatory=true state=failed \
        reason="${variant}: generation succeeded but manifest expects refusal" \
        claim_kind=behaviour-probe interface="agent/tools/loom.sh"
    else
      record_check id="${cid}" suite=offline mandatory=true state=failed \
        reason="${variant}: refusal reason mismatch /${pattern}/" \
        claim_kind=behaviour-probe interface="agent/tools/loom.sh"
    fi
    continue
  fi
  # expected success: generation ok + variant-specific assertions.
  reason=""
  [[ "${gen_ok}" == "1" ]] || reason="generation failed: $(head -1 "${vdir}/generate.log")"
  if [[ -z "${reason}" ]]; then
    case "${variant}" in
      hook-ordering)
        want="$(jq -r '.expected_hook_order | join("\n")' "${manifest}" | sed 's|\$CLAUDE_PROJECT_DIR|$DEVIN_PROJECT_DIR|')"
        got="$(jq -r '.PreToolUse[0].hooks[].command' "${ws}/.devin/hooks.v1.json")"
        [[ "${want}" == "${got}" ]] || reason="devin hook order differs from manifest"
        ;;
      paths-with-spaces-and-escaping)
        want="$(jq -r .expected_hook_command "${manifest}" | sed 's|\$CLAUDE_PROJECT_DIR|$DEVIN_PROJECT_DIR|')"
        got="$(jq -r '.PreToolUse[0].hooks[0].command' "${ws}/.devin/hooks.v1.json")"
        [[ "${want}" == "${got}" ]] || reason="hook command not round-tripped byte-exactly (want [${want}] got [${got}])"
        ;;
      transport-override)
        url_b="$(jq -r .mcp_urls.docs_b "${vdir}/resolved-input.json")"
        got="$(jq -r '.mcpServers["docs-b"].args[2] // empty' "${ws}/.devin/mcp_config.json")"
        [[ "${got}" == "${url_b}" ]] || reason="devin bridge override missing (want ${url_b}, got ${got})"
        ;;
      http-only)
        got="$(jq -r '.mcpServers | keys | sort | join(",")' "${ws}/.devin/mcp_config.json")"
        [[ "${got}" == "docs-a,docs-b" ]] || reason="unexpected server set: ${got}"
        ;;
      stdio-only)
        got="$(jq -r '.mcpServers | keys | sort | join(",")' "${ws}/.devin/mcp_config.json")"
        [[ "${got}" == "docs-local" ]] || reason="unexpected server set: ${got}"
        ;;
      empty-configuration)
        got="$(jq -r '.mcpServers | length' "${ws}/.devin/mcp_config.json")"
        [[ "${got}" == "0" ]] || reason="expected zero servers, got ${got}"
        ;;
    esac
  fi
  if [[ -z "${reason}" ]]; then
    record_check id="${cid}" suite=offline mandatory=true state=passed \
      claim_kind=local-structural
  else
    record_check id="${cid}" suite=offline mandatory=true state=failed \
      reason="${reason}" claim_kind=local-structural
  fi
done
