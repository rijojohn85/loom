#!/usr/bin/env bash
# suites/offline/drift.sh — edit and delete generated artifacts, assert
# --check fails; assert orphan detection via the manifest; assert
# single-harness generation works (T043, FR-040). All mutations happen on a
# throwaway copy; the shared workspace is never touched.
set -euo pipefail
E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${E2E_RUN_DIR:?}" "${E2E_WORKSPACE:?}" "${E2E_OFFLINE_DIR:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"

D="${E2E_OFFLINE_DIR}/drift-copy"
rm -rf "${D}"
cp -a "${E2E_WORKSPACE}" "${D}"
reason=""

# 1. Hand edit must fail --check.
cp "${D}/opencode.json" "${D}/opencode.json.bak"
jq '.mcp["docs-a"].url = "https://evil.example"' "${D}/opencode.json.bak" > "${D}/opencode.json"
if (cd "${D}" && ./agent/tools/loom.sh --check >/dev/null 2>&1); then
  reason="--check passed on a hand-edited artifact"
fi
mv "${D}/opencode.json.bak" "${D}/opencode.json"

# 2. Deleted artifact must fail --check.
if [[ -z "${reason}" ]]; then
  mv "${D}/.devin/config.json" "${D}/config.json.bak"
  if (cd "${D}" && ./agent/tools/loom.sh --check >/dev/null 2>&1); then
    reason="--check passed with a deleted artifact"
  fi
  mv "${D}/config.json.bak" "${D}/.devin/config.json"
fi

# 3. Orphan detection via the manifest.
if [[ -z "${reason}" ]]; then
  echo "docs/stray.md" >> "${D}/agent/harness-specs/loom-manifest.txt"
  mkdir -p "${D}/docs" && echo stray > "${D}/docs/stray.md"
  orphan_out="$(cd "${D}" && ./agent/tools/loom.sh --check 2>&1 || true)"
  if [[ "${orphan_out}" != *"ORPHAN"*docs/stray.md* ]]; then
    reason="orphan manifest entry not reported"
  fi
fi

# 4. Single-harness generation works.
if [[ -z "${reason}" ]]; then
  (cd "${D}" && ./agent/tools/loom.sh --check devin >/dev/null 2>&1) \
    || reason="single-harness --check devin fails on clean tree"
fi
rm -rf "${D}"

if [[ -z "${reason}" ]]; then
  record_check id=offline.drift suite=offline mandatory=true state=passed \
    claim_kind=behaviour-probe interface="agent/tools/loom.sh --check"
else
  record_check id=offline.drift suite=offline mandatory=true state=failed \
    reason="${reason}" claim_kind=behaviour-probe \
    interface="agent/tools/loom.sh --check"
fi
