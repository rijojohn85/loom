#!/usr/bin/env bash
# Summarise a lint-review: count checklist lines addressed in the given file.
set -euo pipefail
grep -c '^-' "${1:-/dev/stdin}" || true
