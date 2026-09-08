#!/usr/bin/env bash
# Fixture hook: second PreToolUse gate on Write|Edit. Ordering between this
# and pre-write.sh is what the hook-ordering scenario asserts.
set -euo pipefail
log="${CLAUDE_PROJECT_DIR:?}/hooks/audit.log"
n=0
[[ -f "${log}" ]] && n="$(wc -l < "${log}" | tr -d ' ')"
echo "$((n + 1)) PreToolUse Write pre-write-check.sh" >> "${log}"
exit 0
