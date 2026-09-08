#!/usr/bin/env bash
# probes/_adapter.sh — shared helpers for harness probe adapters (T070).
# Sourced by probes/<harness>.sh. Every probe function prints one JSON object
# to stdout and returns 0 (ok), 3 (blocked/unverified) or 1 (failure).
# Payloads always include harness_version_observed and interface.
: "${E2E_ROOT:?}"

probe_emit() {  # <harness> <version> <interface> <status> <reason> [data-json]
  local harness="$1" version="$2" interface="$3" status="$4" reason="$5"
  # NOTE: never `${6:-{}}` — bash reads the default as `{` plus a literal
  # `}`, silently appending a brace to every payload.
  local data="{}"
  [[ -n "${6:-}" ]] && data="$6"
  jq -c -n --arg h "${harness}" --arg v "${version}" --arg i "${interface}" \
    --arg s "${status}" --arg r "${reason}" --argjson d "${data}" \
    '{harness: $h, harness_version_observed: $v, interface: $i,
      status: $s, reason: $r, data: $d}'
  case "${status}" in
    ok) return 0 ;;
    blocked|unverified) return 3 ;;
    *) return 1 ;;
  esac
}

probe_cli_version() {  # <harness> — observed version or empty
  case "$1" in
    claude) claude --version 2>/dev/null | awk '{print $1}' ;;
    codex) codex --version 2>/dev/null | awk '{print $2}' ;;
    opencode) opencode --version 2>/dev/null | awk '{print $1}' ;;
  esac
  return 0
}
