#!/usr/bin/env bash
# suites/offline/idempotence.sh — repeat generation from frozen inputs is
# byte-identical, and --check passes without modifying any file (T041).
set -euo pipefail
E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${E2E_RUN_DIR:?}" "${E2E_WORKSPACE:?}" "${E2E_OFFLINE_DIR:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"

snap1="${E2E_OFFLINE_DIR}/idempotence-1.txt"
snap2="${E2E_OFFLINE_DIR}/idempotence-2.txt"
(cd "${E2E_WORKSPACE}" && ./agent/tools/loom.sh >/dev/null 2>&1)
(cd "${E2E_WORKSPACE}" && find .codex .devin opencode.json agent/harness-specs/GAPS.md agent/harness-specs/loom-manifest.txt -type f -exec sha256sum {} + | LC_ALL=C sort) > "${snap1}"
(cd "${E2E_WORKSPACE}" && ./agent/tools/loom.sh >/dev/null 2>&1)
(cd "${E2E_WORKSPACE}" && find .codex .devin opencode.json agent/harness-specs/GAPS.md agent/harness-specs/loom-manifest.txt -type f -exec sha256sum {} + | LC_ALL=C sort) > "${snap2}"

if ! cmp -s "${snap1}" "${snap2}"; then
  record_check id=offline.idempotence suite=offline mandatory=true state=failed \
    reason="repeat generation from frozen inputs is not byte-identical" \
    claim_kind=local-structural
  exit 0
fi

before="$("${E2E_ROOT}/tools/digest.py" "${E2E_WORKSPACE}")"
if (cd "${E2E_WORKSPACE}" && ./agent/tools/loom.sh --check >/dev/null 2>&1); then
  after="$("${E2E_ROOT}/tools/digest.py" "${E2E_WORKSPACE}")"
  if [[ "${before}" == "${after}" ]]; then
    record_check id=offline.idempotence suite=offline mandatory=true state=passed \
      claim_kind=local-structural interface="agent/tools/loom.sh --check"
  else
    record_check id=offline.idempotence suite=offline mandatory=true state=failed \
      reason="--check modified files" claim_kind=local-structural
  fi
else
  record_check id=offline.idempotence suite=offline mandatory=true state=failed \
    reason="--check fails on freshly generated adapters" claim_kind=local-structural
fi
