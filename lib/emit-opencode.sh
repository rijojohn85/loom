#!/usr/bin/env bash

# loom - one AI-agent configuration, woven into the rest.
# Copyright (C) 2026 Rijo John
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, version 3.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public
# License along with this program. If not, see <https://www.gnu.org/licenses/>.

# opencode emitter (loom registry — see ../loom.sh header).
# Spec pack: harness-specs/opencode.md
#
# Emits opencode.json with one `mcp.<name>` remote entry per canonical
# server. The schema rejects unknown keys, so no "_generated_by" marker is
# possible: the --check drift gate is the marker. opencode has no hook
# mechanism and no config-level permission config: every canonical
# permissions entry (allow, deny, ask, defaultMode) and every hook event
# becomes a GAPS row.

emit_opencode() {
  local ir="$1" out="$2"
  mkdir -p "${out}"

  jq -n \
    --slurpfile ir "${ir}" \
    '{ "$schema": "https://opencode.ai/config.json",
       mcp: ([$ir[0].mcp[] | { (.name): { type: "remote", url: .url } }] | add // {}) }' \
    "${ir}" > "${out}/opencode.json"

  local pcontrol kind entry
  pcontrol="$(jq -r '.meta.permission_gap_control | .opencode // .default' "${ir}")"
  while IFS=$'\t' read -r kind entry; do
    [[ -n "${kind}" ]] && gap_add opencode "permission ${kind}: ${entry}" "${pcontrol}"
  done < <(jq -r '
    (.permissions // {}) as $p
    | ([$p.allow[]? | select(startswith("mcp__") | not)] | map(["allow", .]))
    + ([$p.deny[]?]  | map(["deny", .]))
    + ([$p.ask[]?]   | map(["ask", .]))
    + (if ($p.defaultMode // null) == null then [] else [["defaultMode", $p.defaultMode]] end)
    | .[] | @tsv' "${ir}")

  local hcontrol
  hcontrol="$(jq -r '.meta.hook_gap_control | .opencode // .default' "${ir}")"
  while IFS= read -r event; do
    [[ -n "${event}" ]] && gap_add opencode "hook event: ${event}" "${hcontrol}"
  done < <(jq -r '.hooks | keys[]' "${ir}")
}
