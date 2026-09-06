#!/usr/bin/env bash
# suites/offline/docs.sh — self-coverage: run.sh --help and README.md must
# document every flag, suite, exit code and result state the runner
# implements (T104, SC-013). Shares its audit with the mutation suite.
set -euo pipefail
E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${E2E_RUN_DIR:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/mutation/validators.sh"

helpfile="${E2E_RUN_DIR}/offline/help.txt"
"${E2E_ROOT}/run.sh" --help > "${helpfile}"
if reason="$(v_docs_cover "${helpfile}" "${E2E_ROOT}/README.md")"; then
  record_check id=offline.docs suite=offline mandatory=true state=passed \
    claim_kind=local-structural reason=""
else
  record_check id=offline.docs suite=offline mandatory=true state=failed \
    reason="${reason:0:300}" claim_kind=local-structural
fi
