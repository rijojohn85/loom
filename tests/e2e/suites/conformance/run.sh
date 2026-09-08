#!/usr/bin/env bash
# suites/conformance/run.sh — harness loader probes (T075–T082, US4).
# Codex and opencode demonstrably load the generated adapters; Claude is the
# baseline; Devin stays honestly unverified. Missing required harnesses and
# --pinned version mismatches report blocked (exit 3 in full mode, FR-047);
# a deferred Devin alone never triggers exit 3 (FR-043a).
set -euo pipefail

E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export E2E_ROOT
: "${E2E_RUN_DIR:?}" "${E2E_HARNESSES:?}"
REPO_ROOT="$(cd "${E2E_ROOT}/../.." && pwd)"
export REPO_ROOT

# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/workspace.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/isolate.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/trust.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/install.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/offline/materialize.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/conformance/canary.sh"

CONF_DIR="${E2E_RUN_DIR}/conformance"
mkdir -p "${CONF_DIR}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/conformance/mcp.sh"
# Real home captured before any isolate_env call (for credential injection).
REAL_HOME="${HOME}"
export REAL_HOME

declare -A H_BLOCKED=() H_ADVISORY=()

# conf_check <harness> <check-id> <probe-json> <claim-when-clean> [mandatory] [evidence]
conf_check() {
  local h="$1" cid="$2" payload="$3" claim="$4" mandatory="${5:-true}" ev_extra="${6:-}"
  local status reason iface ver pinned="true"
  status="$(jq -r .status <<<"${payload}" 2>/dev/null || echo failed)"
  reason="$(jq -r .reason <<<"${payload}" 2>/dev/null || echo "")"
  iface="$(jq -r .interface <<<"${payload}" 2>/dev/null || echo "")"
  ver="$(jq -r .harness_version_observed <<<"${payload}" 2>/dev/null || echo "")"
  [[ "${status}" =~ ^(ok|blocked|failed|unverified)$ ]] || status="failed"
  if [[ "${H_BLOCKED[${h}]:-0}" == "1" ]]; then
    status="blocked"
    reason="version mismatch under --pinned: see conformance.${h}.version (refresh via the loom skill Phase A workflow)"
    claim="none"
  elif [[ "${H_ADVISORY[${h}]:-0}" == "1" ]]; then
    pinned="false"
    claim="local-structural"
    [[ -n "${reason}" ]] || reason="advisory: observed version differs from pin"
  fi
  local state="${status}"
  [[ "${status}" == "ok" ]] && state="passed"
  # Check states have no `unverified` (that is a capability state):
  # deferred probes are recorded `skipped` (deliberately not run).
  [[ "${status}" == "unverified" ]] && state="skipped"
  local -a args=(id="${cid}" suite=conformance "mandatory=${mandatory}"
    "state=${state}" "claim_kind=${claim}" "harness=${h}" "pinned=${pinned}")
  [[ -n "${reason}" ]] && args+=("reason=${reason}")
  [[ -n "${ver}" ]] && args+=("version=${ver}")
  [[ -n "${iface}" ]] && args+=("interface=${iface}")
  [[ -n "${ev_extra}" ]] && args+=("evidence=${ev_extra}")
  # shellcheck disable=SC2086
  record_check "${args[@]}"
}

# version_gate <harness> -> 0 proceed, 1 pinned-block, 2 advisory
version_gate() {
  local h="$1" payload status reason
  # shellcheck disable=SC1091,SC1090
  source "${E2E_ROOT}/probes/${h}.sh"
  payload="$(probe_version "unused" || true)"
  status="$(jq -r .status <<<"${payload}")"
  reason="$(jq -r .reason <<<"${payload}")"
  if [[ "${status}" == "ok" || "${status}" == "blocked" ]]; then
    conf_check "${h}" "conformance.${h}.version" "${payload}" local-structural \
      "$([[ "${h}" == "devin" ]] && echo false || echo true)"
    [[ "${status}" == "blocked" ]] && return 1
    return 0
  fi
  # status == failed (mismatch; probe_version only fails on mismatch/absent)
  if [[ "${reason}" == *"mismatch"* ]]; then
    if [[ "${E2E_PINNED:-false}" == "true" ]]; then
      H_BLOCKED["${h}"]=1
      conf_check "${h}" "conformance.${h}.version" \
        "$(jq -c '.status = "blocked" | .reason += " (pinned: layer blocked; refresh via the loom skill Phase A workflow)"' <<<"${payload}")" \
        none true
      return 1
    fi
    # Advisory: the check succeeds at detecting + labelling the drift; every
    # outcome in this layer is marked pinned:false (T080, FR-057b).
    H_ADVISORY["${h}"]=1
    conf_check "${h}" "conformance.${h}.version" \
      "$(jq -c --arg r "${reason} (advisory: observed version differs from pin — outcomes unpinned)" \
        '.status = "ok" | .reason = $r' <<<"${payload}")" \
      local-structural true
    return 0
  fi
  conf_check "${h}" "conformance.${h}.version" "${payload}" local-structural true
  return 1
}

# harness_ws <harness> <tag> — build, isolate, install, materialize (UNSEEDED;
# the canary seeds itself so the unseeded state is observable first).
# Sets HARNESS_WS (command substitution would lose the isolation exports).
harness_ws() {
  local h="$1" tag="$2" ws
  make_workspace "${E2E_ROOT}/fixtures/complete-claude" >/dev/null
  ws="${E2E_WORKSPACE}"
  isolate_env
  export E2E_WORKSPACE="${ws}"
  # Claude model-driven probes need the login; loader probes do not.
  if [[ "${h}" == "claude" ]]; then
    inject_claude_credentials "${REAL_HOME}" >/dev/null 2>&1 || true
  fi
  install_loom "${ws}" "${CONF_DIR}/${tag}-install.log" >/dev/null 2>&1 || return 1
  materialize_variant "base" "${ws}" "${CONF_DIR}/${tag}-state" >/dev/null 2>&1 || return 1
  (cd "${ws}" && ./agent/tools/loom.sh >"${CONF_DIR}/${tag}-generate.log" 2>&1) || return 1
  HARNESS_WS="${ws}"
}

checks_for() {  # <harness> -> check-name list (without available/version)
  case "$1" in
    codex) echo "isolated loaded-config unknown-field mcp-list mcp-call context-in-prompt untrusted-canary customisation-negative" ;;
    opencode) echo "isolated loaded-config unknown-field mcp-list mcp-call untrusted-canary customisation-negative" ;;
    claude) echo "mcp-list mcp-call untrusted-canary customisation-negative" ;;
  esac
}

IFS=',' read -ra HARNESSES <<< "${E2E_HARNESSES:-claude,codex,opencode,devin}"

# ---- Devin: no workspace, no invented interface (T074, T082)
if [[ " ${HARNESSES[*]} " == *" devin "* ]]; then
  # shellcheck disable=SC1091
  source "${E2E_ROOT}/probes/devin.sh"
  conf_check devin conformance.devin.available "$(probe_available x || true)" none false
  for fn in version isolated loaded_config unknown_field mcp_list mcp_call \
            context_loaded permission hook_audit native_assets; do
    conf_check devin "conformance.devin.${fn}" "$(probe_${fn} x || true)" none false
  done
fi

for h in "${HARNESSES[@]}"; do
  [[ "${h}" == "devin" ]] && continue
  # shellcheck disable=SC1091,SC1090
  source "${E2E_ROOT}/probes/${h}.sh"

  # Availability gates everything (T082).
  avail="$(probe_available x || true)"
  if [[ "$(jq -r .status <<<"${avail}")" == "blocked" ]]; then
    conf_check "${h}" "conformance.${h}.available" "${avail}" none true
    for c in version $(checks_for "${h}"); do
      record_check id="conformance.${h}.${c}" suite=conformance mandatory=true \
        state=blocked reason="${h} CLI absent" claim_kind=none harness="${h}"
    done
    continue
  fi
  conf_check "${h}" "conformance.${h}.available" "${avail}" none true

  if ! version_gate "${h}"; then
    for c in $(checks_for "${h}"); do
      if [[ "${H_BLOCKED[${h}]:-0}" == "1" ]]; then
        record_check id="conformance.${h}.${c}" suite=conformance mandatory=true \
          state=blocked \
          reason="version mismatch under --pinned (see conformance.${h}.version)" \
          claim_kind=none harness="${h}"
      else
        record_check id="conformance.${h}.${c}" suite=conformance mandatory=true \
          state=blocked reason="version probe failed" \
          claim_kind=none harness="${h}"
      fi
    done
    continue
  fi

  if ! harness_ws "${h}" "${h}"; then
    for c in $(checks_for "${h}"); do
      record_check id="conformance.${h}.${c}" suite=conformance mandatory=true \
        state=blocked reason="workspace build failed" claim_kind=none harness="${h}"
    done
    continue
  fi
  ws="${HARNESS_WS}"
  export E2E_WORKSPACE="${ws}"
  RESOLVED="${CONF_DIR}/${h}-state/resolved-input.json"

  # Trust canary first (seeds itself unless --no-trust-seed) (T075).
  canary_check "${h}" "${ws}"
  # Customisation negative control (T076).
  negative_control "${h}" "${ws}"

  conf_check "${h}" "conformance.${h}.isolated" \
    "$(probe_isolated "${ws}" || true)" harness-loader-probe
  conf_check "${h}" "conformance.${h}.loaded-config" \
    "$(probe_loaded_config "${ws}" || true)" harness-loader-probe

  case "${h}" in
    codex)
      conf_check codex conformance.codex.unknown-field \
        "$(probe_unknown_field "${ws}" || true)" harness-loader-probe
      conf_check codex conformance.codex.mcp-list \
        "$(probe_mcp_list "${ws}" || true)" harness-loader-probe
      conf_check codex conformance.codex.context-in-prompt \
        "$(probe_context_loaded "${ws}" || true)" harness-loader-probe ;;
    opencode)
      conf_check opencode conformance.opencode.unknown-field \
        "$(probe_unknown_field "${ws}" || true)" official-schema
      conf_check opencode conformance.opencode.mcp-list \
        "$(probe_mcp_list "${ws}" || true)" harness-loader-probe ;;
    claude)
      conf_check claude conformance.claude.mcp-list \
        "$(probe_mcp_list "${ws}" || true)" harness-loader-probe ;;
  esac

  # MCP call against live fixture services (T078; see suites/conformance/mcp.sh).
  if [[ "${h}" == "codex" || "${h}" == "opencode" || "${h}" == "claude" ]]; then
    mcp_conformance "${h}" "${ws}" "${RESOLVED}"
  fi
done
