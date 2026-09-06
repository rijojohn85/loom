#!/usr/bin/env bash
# suites/offline/schema.sh — official-schema validation for opencode (T040).
# Runs tools/schema_validate.py against the vendored schema with the pinned
# jsonschema. A missing venv reports blocked (never skipped, never passed).
set -euo pipefail
E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${E2E_RUN_DIR:?}" "${E2E_WORKSPACE:?}" "${E2E_OFFLINE_DIR:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"

SCHEMA="${E2E_ROOT}/schemas/opencode.config.schema.json"
SCHEMA_DIGEST="$(sha256sum "${SCHEMA}" | awk '{print $1}')"
set +e
# The pinned validator must run under the bootstrapped venv; the system
# python has no jsonschema and honestly reports blocked (exit 3).
PY=python3
[[ -x "${E2E_ROOT}/.venv/bin/python" ]] && PY="${E2E_ROOT}/.venv/bin/python"
out="$("${PY}" "${E2E_ROOT}/tools/schema_validate.py" "${SCHEMA}" \
  "${E2E_WORKSPACE}/opencode.json" 2>"${E2E_OFFLINE_DIR}/schema.err")"
code=$?
set -e
echo "${out}" > "${E2E_OFFLINE_DIR}/schema.json"
case "${code}" in
  0) record_check id=offline.schema suite=offline mandatory=true state=passed \
       claim_kind=official-schema \
       interface="tools/schema_validate.py schemas/opencode.config.schema.json" \
       reason="" ;;
  3) record_check id=offline.schema suite=offline mandatory=true state=blocked \
       reason="bootstrapped venv absent — run tests/e2e/run.sh --bootstrap (schema ${SCHEMA_DIGEST:0:12})" \
       claim_kind=official-schema ;;
  *) record_check id=offline.schema suite=offline mandatory=true state=failed \
       reason="opencode.json fails official schema: ${out:0:300}" \
       claim_kind=official-schema ;;
esac
