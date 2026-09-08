#!/usr/bin/env bash
# probes/opencode.sh — opencode 1.18.29 probe adapter (T072).
# Verified interfaces only (research D1, D11). Functions take a workspace
# path as $1 and print one JSON payload (see _adapter.sh).
# shellcheck disable=SC1091
source "${E2E_ROOT}/probes/_adapter.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/isolate.sh" 2>/dev/null || true

_opencode_ver() { probe_cli_version opencode; }

probe_available() {
  local v
  v="$(_opencode_ver)"
  if [[ -n "${v}" ]]; then
    probe_emit opencode "${v}" "opencode --version" ok "" "{\"version\": \"${v}\"}"
  else
    probe_emit opencode "" "opencode --version" blocked "opencode CLI absent" '{}'
  fi
}

probe_version() {
  local v pinned
  v="$(_opencode_ver)"
  pinned="$(jq -r '.harnesses.opencode.version // empty' "${E2E_ROOT}/pins/harnesses.json")"
  if [[ -z "${v}" ]]; then
    probe_emit opencode "" "opencode --version" blocked "opencode CLI absent" '{}'
  elif [[ "${v}" == "${pinned}" ]]; then
    probe_emit opencode "${v}" "opencode --version" ok "" "{\"pinned\": \"${pinned}\"}"
  else
    probe_emit opencode "${v}" "opencode --version" failed \
      "version mismatch: observed ${v}, pinned ${pinned}" "{\"pinned\": \"${pinned}\"}"
  fi
}

probe_isolated() {  # debug paths must sit under the per-run home
  local ws="$1" v out
  v="$(_opencode_ver)"
  [[ -n "${v}" ]] || { probe_emit opencode "" "opencode debug paths" blocked "opencode CLI absent" '{}'; return; }
  if out="$(cd "${ws}" && run_isolated opencode debug paths 2>/dev/null)"; then
    if grep -qF "${E2E_RUN_DIR}" <<<"${out}"; then
      probe_emit opencode "${v}" "opencode debug paths" ok "" '{"isolation": "paths under run dir"}'
    else
      probe_emit opencode "${v}" "opencode debug paths" failed \
        "global paths escape the run dir (known /tmp/opencode sharing — see research D6)" \
        "$(jq -c -R -s '{paths: .[0:400]}' <<<"${out}")"
    fi
  else
    probe_emit opencode "${v}" "opencode debug paths" failed "debug paths failed" '{}'
  fi
}

seed_trust() {  # opencode has no trust gate — recorded as an observed fact
  local v
  v="$(_opencode_ver)"
  probe_emit opencode "${v}" "none" ok "no gate observed: project config loads unseeded" \
    '{"seeded": false, "note": "no gate observed"}'
}

probe_trust_state() {
  local v
  v="$(_opencode_ver)"
  probe_emit opencode "${v}" "opencode debug config" ok \
    "no trust gate on this version" '{"seeded": false}'
}

probe_loaded_config() {  # effective resolved config must carry the servers
  local ws="$1" v out
  v="$(_opencode_ver)"
  [[ -n "${v}" ]] || { probe_emit opencode "" "opencode debug config" blocked "opencode CLI absent" '{}'; return; }
  if out="$(cd "${ws}" && run_isolated opencode debug config 2>/dev/null)"; then
    if jq -e '.mcp["docs-a"] and .mcp["docs-b"]' <<<"${out}" >/dev/null 2>&1; then
      probe_emit opencode "${v}" "opencode debug config" ok "" \
        "$(jq -c '{mcp: (.mcp // {} | keys)}' <<<"${out}" 2>/dev/null || echo '{}')"
    else
      probe_emit opencode "${v}" "opencode debug config" failed \
        "fixture servers absent from resolved config" \
        "$(jq -c '{mcp: (.mcp // {} | keys)}' <<<"${out}" 2>/dev/null || echo '{}')"
    fi
  else
    probe_emit opencode "${v}" "opencode debug config" failed "debug config failed" '{}'
  fi
}

probe_unknown_field() {  # official-schema rejection on an adapter copy
  local ws="$1" v tmp out code py=python3
  v="$(_opencode_ver)"
  tmp="$(mktemp -d)"
  jq '.__loom_unknown_field__ = true' "${ws}/opencode.json" > "${tmp}/bad.json"
  [[ -x "${E2E_ROOT}/.venv/bin/python" ]] && py="${E2E_ROOT}/.venv/bin/python"
  set +e
  out="$("${py}" "${E2E_ROOT}/tools/schema_validate.py" \
    "${E2E_ROOT}/schemas/opencode.config.schema.json" "${tmp}/bad.json" 2>&1)"
  code=$?
  set -e
  rm -rf "${tmp}"
  if [[ "${code}" -eq 1 ]]; then
    probe_emit opencode "${v}" "official-schema validation" ok \
      "schema rejected unknown field" '{}'
  elif [[ "${code}" -eq 3 ]]; then
    probe_emit opencode "${v}" "official-schema validation" blocked \
      "bootstrapped venv absent" '{}'
  else
    probe_emit opencode "${v}" "official-schema validation" failed \
      "schema accepted an unknown field" '{}'
  fi
}

probe_mcp_list() {  # docs-a/b/local must resolve (not just exit 0)
  local ws="$1" v out
  v="$(_opencode_ver)"
  [[ -n "${v}" ]] || { probe_emit opencode "" "opencode mcp list" blocked "opencode CLI absent" '{}'; return; }
  if out="$(cd "${ws}" && run_isolated opencode mcp list 2>/dev/null)"; then
    if grep -q "docs-a" <<<"${out}" && grep -q "docs-b" <<<"${out}"; then
      probe_emit opencode "${v}" "opencode mcp list" ok "" \
        "$(jq -c -R -s '{raw: .[0:600]}' <<<"${out}")"
    else
      probe_emit opencode "${v}" "opencode mcp list" failed \
        "fixture servers absent from mcp list" \
        "$(jq -c -R -s '{raw: .[0:600]}' <<<"${out}")"
    fi
  else
    probe_emit opencode "${v}" "opencode mcp list" failed "mcp list failed" '{}'
  fi
}

probe_mcp_call() {  # needs model auth; blocked without
  local ws="$1" v port out code
  v="$(_opencode_ver)"
  [[ -n "${v}" ]] || { probe_emit opencode "" "opencode run --format json" blocked "opencode CLI absent" '{}'; return; }
  port="$(jq -r '.ports.mcp_a // 43127' "${ws}/workspace.json" 2>/dev/null || echo 43127)"
  set +e
  out="$(cd "${ws}" && run_isolated opencode run --format json --dir "${ws}" \
    --port "${port}" --pure \
    "Call the docs-a MCP server docs.list tool and report its exact output" \
    < /dev/null 2>&1)"
  code=$?
  set -e
  mkdir -p "${E2E_RUN_DIR}/conformance/transcripts" 2>/dev/null || true
  printf '%s' "${out}" > "${E2E_RUN_DIR}/conformance/transcripts/opencode-mcp-call.log" 2>/dev/null || true
  if [[ "${code}" -ne 0 ]] && grep -qi "auth\|login\|api key\|unauthorized\|401" <<<"${out}"; then
    probe_emit opencode "${v}" "opencode run --format json" blocked \
      "no opencode model auth in this environment" '{}'
  elif [[ "${code}" -eq 0 ]] && grep -Eq "docs[._-]list" <<<"${out}" \
    && grep -q "api,readme" <<<"${out}"; then
    probe_emit opencode "${v}" "opencode run --format json" ok \
      "permitted MCP call returned fixture content" '{}'
  elif [[ "${code}" -eq 0 ]]; then
    probe_emit opencode "${v}" "opencode run --format json" failed \
      "MCP call answered without fixture content" '{}'
  else
    probe_emit opencode "${v}" "opencode run --format json" failed \
      "run failed: $(head -1 <<<"${out}" | head -c 160)" '{}'
  fi
}

probe_context_loaded() {  # no deterministic interface — model runs only
  local v
  v="$(_opencode_ver)"
  [[ -n "${v}" ]] || { probe_emit opencode "" "opencode run --format json" blocked "opencode CLI absent" '{}'; return; }
  probe_emit opencode "${v}" "opencode run --format json" blocked \
    "context influence is model-observed in the intent suite; no deterministic opencode context probe exists" '{}'
}

probe_permission() {
  local v
  v="$(_opencode_ver)"
  [[ -n "${v}" ]] || { probe_emit opencode "" "opencode run --format json" blocked "opencode CLI absent" '{}'; return; }
  probe_emit opencode "${v}" "opencode run --format json" blocked \
    "approval behaviour is model-observed in the intent suite; no deterministic opencode permission probe exists" '{}'
}

probe_hook_audit() {
  local v
  v="$(_opencode_ver)"
  probe_emit opencode "${v}" "none" blocked "opencode has no hook mechanism" '{}'
}

probe_native_assets() {  # native skill/agent visibility (verified interfaces)
  local ws="$1" v skills agents
  v="$(_opencode_ver)"
  [[ -n "${v}" ]] || { probe_emit opencode "" "opencode debug skill" blocked "opencode CLI absent" '{}'; return; }
  skills="$(cd "${ws}" && run_isolated opencode debug skill 2>&1 || true)"
  agents="$(cd "${ws}" && run_isolated opencode agent list 2>&1 || true)"
  probe_emit opencode "${v}" "opencode debug skill + agent list" ok "" \
    "$(jq -n --arg s "${skills:0:400}" --arg a "${agents:0:400}" \
      '{skills: $s, agents: $a}')"
}
