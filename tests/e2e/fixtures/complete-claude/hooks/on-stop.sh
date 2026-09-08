#!/usr/bin/env bash
# Fixture hook: Stop event (no matcher). Records session end.
set -euo pipefail
log="${CLAUDE_PROJECT_DIR:?}/hooks/audit.log"
n=0
[[ -f "${log}" ]] && n="$(wc -l < "${log}" | tr -d ' ')"
echo "$((n + 1)) Stop on-stop.sh" >> "${log}"
exit 0
