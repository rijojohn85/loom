#!/usr/bin/env bash
# Fixture hook: PostToolUse on Write|Edit. Must run after both PreToolUse
# hooks; the audit log order proves it.
set -euo pipefail
log="${CLAUDE_PROJECT_DIR:?}/hooks/audit.log"
n=0
[[ -f "${log}" ]] && n="$(wc -l < "${log}" | tr -d ' ')"
echo "$((n + 1)) PostToolUse Write post-write.sh" >> "${log}"
exit 0
