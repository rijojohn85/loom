#!/usr/bin/env bash
# Devin emitter (loom registry — see ../loom.sh header).
# Spec pack: harness-specs/devin.md
#
# Three files under .devin/:
#   mcp_config.json  per-server transport; servers listed under
#                    mcp_overrides.devin in loom.config.json use a
#                    {command, args} stdio bridge ("{{url}}" is substituted),
#                    the rest connect natively over HTTP
#   config.json      permissions.allow, mcp__<server>__* entries only
#   hooks.v1.json    the canonical Claude hooks, $CLAUDE_PROJECT_DIR rewritten
#                    to $DEVIN_PROJECT_DIR, empty matcher, 30s timeout

emit_devin() {
  local ir="$1" out="$2"
  local dir="${out}/.devin"
  mkdir -p "${dir}"

  jq -n \
    --slurpfile ir "${ir}" \
    --arg src "source: $(jq -r '.meta.mcp_json' "${ir}") + $(jq -r '.meta.config_path' "${ir}")" \
    '
    { "_generated_by": ("loom — do not edit by hand; " + $src),
      mcpServers: ($ir[0].mcp | map(
        .url as $u | (.overrides.devin // {})[.name] as $ov |
        if $ov
        then { (.name): { command: $ov.command,
                          args: [$ov.args[] | gsub("\\{\\{url\\}\\}"; $u)] } }
        else { (.name): { url: .url, transport: "http" } }
        end
      ) | add // {}) }' "${ir}" > "${dir}/mcp_config.json"

  jq -n \
    --slurpfile ir "${ir}" \
    --arg src "source: .claude/settings.json" \
    '{ "_generated_by": ("loom — do not edit by hand; " + $src),
       permissions: {
         allow: [($ir[0].permissions.allow // [])[] | select(startswith("mcp__"))]
       } }' "${ir}" > "${dir}/config.json"

  local pcontrol
  pcontrol="$(jq -r '.meta.permission_gap_control | .devin // .default' "${ir}")"
  while IFS= read -r entry; do
    [[ -n "${entry}" ]] && gap_add devin "permission allow: ${entry}" "${pcontrol}"
  done < <(jq -r '(.permissions.allow // [])[] | select(startswith("mcp__") | not)' "${ir}")

  # Every canonical hook event Devin supports is carried over verbatim
  # (Devin: PreToolUse denies on exit 2, like Claude Code). Unsupported
  # events become GAPS rows rather than silent loss.
  local devin_events="PreToolUse PostToolUse PermissionRequest UserPromptSubmit Stop PostCompaction SessionStart SessionEnd"
  local hcontrol
  hcontrol="$(jq -r '.meta.hook_gap_control | .devin // .default' "${ir}")"
  while IFS= read -r event; do
    [[ -n "${event}" ]] || continue
    if [[ " ${devin_events} " != *" ${event} "* ]]; then
      gap_add devin "hook event: ${event}" "${hcontrol}"
    fi
  done < <(jq -r '.hooks | keys[]' "${ir}")

  jq -n \
    --slurpfile ir "${ir}" \
    --arg src "source: .claude/settings.json" \
    --arg supported "${devin_events}" \
    '{ "_generated_by": ("loom — do not edit by hand; " + $src) }
     + ($ir[0].hooks
        | with_entries(select(.key as $k | ($supported | split(" ")) | index($k)))
        | with_entries(.value |= [ .[] | {
            matcher: "",
            hooks: [{ type: "command",
                      command: (.hooks[0].command | sub("\\$CLAUDE_PROJECT_DIR"; "$DEVIN_PROJECT_DIR")),
                      timeout: 30 }]
          } ]))' "${ir}" > "${dir}/hooks.v1.json"
}
