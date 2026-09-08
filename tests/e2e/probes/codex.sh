#!/usr/bin/env bash
# probes/codex.sh — Codex 0.153.4 probe adapter (T071).
# Verified interfaces only (research D1, D11, D12). Functions take a workspace
# path as $1 and print one JSON payload (see _adapter.sh).
# shellcheck disable=SC2155
# shellcheck disable=SC1091
source "${E2E_ROOT}/probes/_adapter.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/isolate.sh" 2>/dev/null || true

_codex_ver() { probe_cli_version codex; }

probe_available() {  # -> ok when the CLI runs
  local v
  v="$(_codex_ver)"
  if [[ -n "${v}" ]]; then
    probe_emit codex "${v}" "codex --version" ok "" "{\"version\": \"${v}\"}"
  else
    probe_emit codex "" "codex --version" blocked "codex CLI absent" '{}'
  fi
}

probe_version() {
  local v pinned
  v="$(_codex_ver)"
  pinned="$(jq -r '.harnesses.codex.version // empty' "${E2E_ROOT}/pins/harnesses.json")"
  if [[ -z "${v}" ]]; then
    probe_emit codex "" "codex --version" blocked "codex CLI absent" '{}'
  elif [[ "${v}" == "${pinned}" ]]; then
    probe_emit codex "${v}" "codex --version" ok "" "{\"pinned\": \"${pinned}\"}"
  else
    probe_emit codex "${v}" "codex --version" failed \
      "version mismatch: observed ${v}, pinned ${pinned}" "{\"pinned\": \"${pinned}\"}"
  fi
}

probe_isolated() {  # user state must come from the per-run paths only
  local ws="$1" v out
  v="$(_codex_ver)"
  [[ -n "${v}" ]] || { probe_emit codex "" "codex doctor --json" blocked "codex CLI absent" '{}'; return; }
  case "${CODEX_HOME:-}" in
    "${E2E_RUN_DIR:-__unset__}"/*) ;;
    *) probe_emit codex "${v}" "codex doctor --json" failed \
         "CODEX_HOME (${CODEX_HOME:-unset}) escapes the run directory" '{}'; return ;;
  esac
  # doctor exits nonzero when overallStatus is fail (e.g. no login) but
  # still prints the machine-readable report — judge content, not the code.
  out="$(cd "${ws}" && run_isolated codex doctor --json 2>/dev/null || true)"
  if jq -e . >/dev/null 2>&1 <<<"${out:-}"; then
    if grep -qF "${CODEX_HOME}" <<<"${out}"; then
      probe_emit codex "${v}" "codex doctor --json" ok "" \
        '{"isolation": "doctor report references per-run CODEX_HOME"}'
      return
    fi
    probe_emit codex "${v}" "codex doctor --json" ok \
      "doctor report parsed; per-run path not referenced (see data)" \
      '{"isolation": "report-parsed"}'
    return
  fi
  if [[ -d "${CODEX_HOME}" ]]; then
    probe_emit codex "${v}" "codex doctor --json" ok \
      "doctor report unavailable; env isolation asserted (CODEX_HOME in run dir)" \
      '{"isolation": "env-only"}'
  else
    probe_emit codex "${v}" "codex doctor --json" failed \
      "per-run CODEX_HOME missing" '{}'
  fi
}

seed_trust() {  # delegates to the single trust implementation (lib/trust.sh)
  local ws="$1"; shift
  # shellcheck disable=SC1091
  source "${E2E_ROOT}/lib/trust.sh" 2>/dev/null || true
  local v
  v="$(_codex_ver)"
  if seed_trust "${ws}" "$@"; then
    probe_emit codex "${v}" "trust-seed into \$CODEX_HOME/config.toml" ok "" \
      "{\"workspace\": \"${ws}\"}"
  else
    probe_emit codex "${v}" "trust-seed into \$CODEX_HOME/config.toml" failed \
      "seed_trust refused or failed" '{}'
  fi
}

probe_trust_state() {  # what changed: server count before/after seeding is the caller's job
  local ws="$1" v out n
  v="$(_codex_ver)"
  [[ -n "${v}" ]] || { probe_emit codex "" "codex mcp list --json" blocked "codex CLI absent" '{}'; return; }
  if out="$(cd "${ws}" && run_isolated codex mcp list --json 2>/dev/null)"; then
    n="$(jq 'length' <<<"${out}" 2>/dev/null || echo -1)"
    probe_emit codex "${v}" "codex mcp list --json" ok "" "{\"servers\": ${n}}"
  else
    probe_emit codex "${v}" "codex mcp list --json" failed "mcp list failed" '{}'
  fi
}

probe_loaded_config() {  # effective loaded config, not a re-parse of our file
  local ws="$1" v out
  v="$(_codex_ver)"
  [[ -n "${v}" ]] || { probe_emit codex "" "codex doctor --json" blocked "codex CLI absent" '{}'; return; }
  # doctor exits nonzero on overallStatus fail yet still prints the report.
  out="$(cd "${ws}" && run_isolated codex doctor --json 2>/dev/null || true)"
  if jq -e '.codexVersion and .checks' >/dev/null 2>&1 <<<"${out:-}"; then
    probe_emit codex "${v}" "codex doctor --json" ok "" \
      "$(jq -c '{codexVersion, overallStatus}' <<<"${out}" 2>/dev/null || echo '{}')"
  else
    probe_emit codex "${v}" "codex doctor --json" failed \
      "no machine-readable doctor report" '{}'
  fi
}

probe_unknown_field() {  # strict gate on the isolated USER config (D12)
  local ws="$1" v cfg backup out code
  v="$(_codex_ver)"
  [[ -n "${v}" ]] || { probe_emit codex "" "codex exec --strict-config" blocked "codex CLI absent" '{}'; return; }
  cfg="${CODEX_HOME:?}/config.toml"
  case "${cfg}" in "${E2E_RUN_DIR}"/*) ;;
    *) probe_emit codex "${v}" "codex exec --strict-config" failed \
         "refusing: user config outside run dir" '{}'; return ;; esac
  [[ -f "${cfg}" ]] || { probe_emit codex "${v}" "codex exec --strict-config" failed \
    "no user config to test (seed trust first)" '{}'; return; }
  backup="${cfg}.strict-bak"
  cp "${cfg}" "${backup}"
  printf '\n__loom_unknown_field__ = true\n' >> "${cfg}"
  # Config load precedes any model/auth step, so a working gate fails fast
  # with no spend. timeout bounds the regression case (field accepted).
  set +e
  out="$(cd "${ws}" && run_isolated timeout 60 codex exec --strict-config \
    --sandbox read-only --skip-git-repo-check "reply ok" < /dev/null 2>&1)"
  code=$?
  set -e
  mv "${backup}" "${cfg}"
  if [[ "${code}" -ne 0 ]] && grep -qi "unknown.*field\|not recognized" <<<"${out}"; then
    probe_emit codex "${v}" "codex exec --strict-config" ok \
      "loader rejected unknown user-config field" \
      "{\"evidence\": $(jq -R -s . <<<"$(grep -i "unknown.*field\|not recognized" <<<"${out}" | head -1)")}"
  else
    probe_emit codex "${v}" "codex exec --strict-config" failed \
      "loader did not reject unknown user-config field (exit ${code})" '{}'
  fi
}

probe_mcp_list() {  # docs-a/b/local must resolve (not just exit 0)
  local ws="$1" v out
  v="$(_codex_ver)"
  [[ -n "${v}" ]] || { probe_emit codex "" "codex mcp list --json" blocked "codex CLI absent" '{}'; return; }
  if out="$(cd "${ws}" && run_isolated codex mcp list --json 2>/dev/null)"; then
    if jq -e 'map(.name) | index("docs-a") and index("docs-b") and index("docs-local")' \
        <<<"${out}" >/dev/null 2>&1; then
      probe_emit codex "${v}" "codex mcp list --json" ok "" \
        "$(jq -c '{servers: [.[].name]}' <<<"${out}" 2>/dev/null || echo '{}')"
    else
      probe_emit codex "${v}" "codex mcp list --json" failed \
        "fixture servers absent from mcp list" \
        "$(jq -c '{servers: [.[].name]}' <<<"${out}" 2>/dev/null || echo '{}')"
    fi
  else
    probe_emit codex "${v}" "codex mcp list --json" failed "mcp list failed" '{}'
  fi
}

probe_mcp_call() {  # one permitted call — needs model auth; blocked without
  local ws="$1" v out code
  v="$(_codex_ver)"
  [[ -n "${v}" ]] || { probe_emit codex "" "codex exec --json" blocked "codex CLI absent" '{}'; return; }
  set +e
  out="$(cd "${ws}" && run_isolated codex exec --json -C "${ws}" \
    --sandbox read-only --skip-git-repo-check \
    "Call the docs-a MCP server docs.list tool and report its exact output" \
    < /dev/null 2>&1)"
  code=$?
  set -e
  mkdir -p "${E2E_RUN_DIR}/conformance/transcripts" 2>/dev/null || true
  printf '%s' "${out}" > "${E2E_RUN_DIR}/conformance/transcripts/codex-mcp-call.log" 2>/dev/null || true
  if [[ "${code}" -ne 0 ]] && grep -qi "unauthorized\|auth\|login\|api key" <<<"${out}"; then
    probe_emit codex "${v}" "codex exec --json" blocked \
      "no codex model auth in this environment" '{}'
  elif [[ "${code}" -eq 0 ]] && grep -Eq "docs[._-]list" <<<"${out}" \
    && grep -q "api,readme" <<<"${out}"; then
    probe_emit codex "${v}" "codex exec --json" ok \
      "permitted MCP call returned fixture content" '{}'
  elif [[ "${code}" -eq 0 ]]; then
    probe_emit codex "${v}" "codex exec --json" failed \
      "MCP call answered without fixture content" '{}'
  else
    probe_emit codex "${v}" "codex exec --json" failed \
      "exec failed: $(head -1 <<<"${out}" | head -c 160)" '{}'
  fi
}

probe_context_loaded() {  # canary from AGENTS.md in the model-visible prompt
  local ws="$1" v out
  v="$(_codex_ver)"
  [[ -n "${v}" ]] || { probe_emit codex "" "codex debug prompt-input" blocked "codex CLI absent" '{}'; return; }
  if out="$(cd "${ws}" && run_isolated codex debug prompt-input 2>/dev/null)"; then
    if grep -q "Never remove a \`deny\` permission" <<<"${out}"; then
      probe_emit codex "${v}" "codex debug prompt-input" ok \
        "fixture context canary present in model-visible prompt" '{}'
    else
      probe_emit codex "${v}" "codex debug prompt-input" failed \
        "fixture context canary absent from model-visible prompt" '{}'
    fi
  else
    probe_emit codex "${v}" "codex debug prompt-input" failed "prompt-input failed" '{}'
  fi
}

probe_permission() {  # refusal behaviour needs a model run
  local v
  v="$(_codex_ver)"
  [[ -n "${v}" ]] || { probe_emit codex "" "codex exec --json" blocked "codex CLI absent" '{}'; return; }
  probe_emit codex "${v}" "codex exec --json --sandbox read-only" blocked \
    "permission scenarios run model-driven in the intent suite; no deterministic codex refusal probe exists" '{}'
}

probe_hook_audit() {
  local v
  v="$(_codex_ver)"
  probe_emit codex "${v}" "none" blocked "codex has no hook mechanism" '{}'
}

probe_native_assets() {
  local v
  v="$(_codex_ver)"
  [[ -n "${v}" ]] || { probe_emit codex "" "none" blocked "codex CLI absent" '{}'; return; }
  probe_emit codex "${v}" "none" blocked \
    "no verified codex skill/agent listing interface; native equivalents recorded from documentation only" '{}'
}
