#!/usr/bin/env bash
# Fixture hook: PostToolUse on Bash. The generator (loom.sh) writes adapters
# with cp inside Bash tool calls, so Write|Edit matchers never see it — this
# hook is the proof that project hooks loaded and ran around the generator
# invocation. Logs the invoked command (truncated) to the audit log.
set -euo pipefail
log="${CLAUDE_PROJECT_DIR:?}/hooks/audit.log"
input="$(cat)"
cmd="$(printf '%s' "${input}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command","")[:120])' 2>/dev/null || true)"
n=0
[[ -f "${log}" ]] && n="$(wc -l < "${log}" | tr -d ' ')"
echo "$((n + 1)) PostToolUse Bash ${cmd}" >> "${log}"
exit 0
