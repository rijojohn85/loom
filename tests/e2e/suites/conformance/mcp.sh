#!/usr/bin/env bash
# suites/conformance/mcp.sh — MCP conformance (T078, T111): initialization,
# tool discovery and one permitted call per harness against the local
# fixture services, started on allocated ports and terminated afterwards
# (FR-046). Sourced by run.sh after CONF_DIR exists.
: "${E2E_RUN_DIR:?}" "${E2E_ROOT:?}" "${CONF_DIR:?}"

# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"

# start_fixture_services <resolved-input-json> -> 0 ok; sets SVC_A SVC_B
start_fixture_services() {
  local res="$1" pa pb
  pa="$(jq -r .ports.mcp_a "${res}")"
  pb="$(jq -r .ports.mcp_b "${res}")"
  python3 "${E2E_ROOT}/fixtures/services/mcp_http.py" "${pa}" \
    "${CONF_DIR}/mcp-audit-a.log" &
  echo $! >> "${E2E_RUN_DIR}/child-pids.lst"
  SVC_A=$!
  python3 "${E2E_ROOT}/fixtures/services/mcp_http.py" "${pb}" \
    "${CONF_DIR}/mcp-b-audit.log" &
  echo $! >> "${E2E_RUN_DIR}/child-pids.lst"
  SVC_B=$!
  sleep 1
  (kill -0 "${SVC_A}" && kill -0 "${SVC_B}") 2>/dev/null
}

# mcp_conformance <harness> <workspace> <resolved-input-json>
mcp_conformance() {
  local h="$1" ws="$2" res="$3" SVC_A SVC_B
  if start_fixture_services "${res}"; then
    conf_check "${h}" "conformance.${h}.mcp-call" \
      "$(probe_mcp_call "${ws}" || true)" behaviour-probe true \
      "conformance/transcripts/${h}-mcp-call.log"
    kill "${SVC_A}" "${SVC_B}" 2>/dev/null || true
    sleep 1
    if kill -0 "${SVC_A}" 2>/dev/null || kill -0 "${SVC_B}" 2>/dev/null; then
      kill -KILL "${SVC_A}" "${SVC_B}" 2>/dev/null || true
    fi
  else
    record_check id="conformance.${h}.mcp-call" suite=conformance \
      mandatory=true state=blocked \
      reason="fixture MCP services failed to start" \
      claim_kind=none harness="${h}"
  fi
}
