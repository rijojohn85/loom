#!/usr/bin/env bash
# probes/devin.sh — Devin deferred adapter (T074, FR-043a, FR-044).
# No local CLI exists and no interface is invented: probe_available reports
# blocked, every other function reports unverified.
# shellcheck disable=SC1091
source "${E2E_ROOT}/probes/_adapter.sh"

probe_available() {
  probe_emit devin "" "none" blocked \
    "no local Devin interface — adapters validated structurally offline" '{}'
}

probe_version() {
  probe_emit devin "" "none" unverified "deferred target: no version to observe" '{}'
}

probe_isolated() {
  probe_emit devin "" "none" unverified "deferred target" '{}'
}

seed_trust() {
  probe_emit devin "" "none" unverified "deferred target: nothing to seed" '{}'
}

probe_trust_state() {
  probe_emit devin "" "none" unverified "deferred target" '{}'
}

probe_loaded_config() {
  probe_emit devin "" "none" unverified "deferred target" '{}'
}

probe_unknown_field() {
  probe_emit devin "" "none" unverified "deferred target" '{}'
}

probe_mcp_list() {
  probe_emit devin "" "none" unverified "deferred target" '{}'
}

probe_mcp_call() {
  probe_emit devin "" "none" unverified "deferred target" '{}'
}

probe_context_loaded() {
  probe_emit devin "" "none" unverified "deferred target" '{}'
}

probe_permission() {
  probe_emit devin "" "none" unverified "deferred target" '{}'
}

probe_hook_audit() {
  probe_emit devin "" "none" unverified "deferred target" '{}'
}

probe_native_assets() {
  probe_emit devin "" "none" unverified "deferred target" '{}'
}
