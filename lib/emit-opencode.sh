#!/usr/bin/env bash
# opencode emitter (loom registry — see ../loom.sh header).
# Spec pack: harness-specs/opencode.md
#
# Emits opencode.json with one `mcp.<name>` remote entry per canonical
# server. The schema rejects unknown keys, so no "_generated_by" marker is
# possible: the --check drift gate is the marker. opencode has no hook
# mechanism and no config-level permission allowlist.

emit_opencode() {
  local ir="$1" out="$2"
  mkdir -p "${out}"

  jq -n \
    --slurpfile ir "${ir}" \
    '{ "$schema": "https://opencode.ai/config.json",
       mcp: ([$ir[0].mcp[] | { (.name): { type: "remote", url: .url } }] | add // {}) }' \
    "${ir}" > "${out}/opencode.json"

  local pcontrol
  pcontrol="$(jq -r '.meta.permission_gap_control | .opencode // .default' "${ir}")"
  while IFS= read -r entry; do
    [[ -n "${entry}" ]] && gap_add opencode "permission allow: ${entry}" "${pcontrol}"
  done < <(jq -r '(.permissions.allow // [])[] | select(startswith("mcp__") | not)' "${ir}")

  local hcontrol
  hcontrol="$(jq -r '.meta.hook_gap_control | .opencode // .default' "${ir}")"
  while IFS= read -r event; do
    [[ -n "${event}" ]] && gap_add opencode "hook event: ${event}" "${hcontrol}"
  done < <(jq -r '.hooks | keys[]' "${ir}")
}
