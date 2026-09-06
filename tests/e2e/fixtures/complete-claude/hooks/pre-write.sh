#!/usr/bin/env bash
# Fixture hook: first PreToolUse gate on Write|Edit. Deterministic and
# harmless: appends one ordered entry to the audit log and exits 0.
set -euo pipefail
log="${CLAUDE_PROJECT_DIR:?}/hooks/audit.log"
n=0
[[ -f "${log}" ]] && n="$(wc -l < "${log}" | tr -d ' ')"
echo "$((n + 1)) PreToolUse Write pre-write.sh" >> "${log}"
exit 0
