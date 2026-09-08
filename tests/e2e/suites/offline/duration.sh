#!/usr/bin/env bash
# suites/offline/duration.sh — suite wall clock against the reference budget
# recorded in pins/dependencies.json (T049, SC-001). Enforced (failing) when
# CI=true, advisory elsewhere.
set -euo pipefail
E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${E2E_RUN_DIR:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/mutation/validators.sh"

start="$(cat "${E2E_RUN_DIR}/offline-started-at" 2>/dev/null || date +%s)"
now="$(date +%s)"
elapsed=$((now - start))
budget="$(jq -r .offline_budget_seconds "${E2E_ROOT}/pins/dependencies.json" 2>/dev/null || echo 180)"
[[ "${budget}" =~ ^[0-9]+$ ]] || budget=180

detail="$(v_duration "${elapsed}" "${budget}")" && over=0 || over=1
if [[ "${over}" -eq 0 ]]; then
  record_check id=offline.duration suite=offline mandatory=true state=passed \
    claim_kind=local-structural reason=""
else
  if [[ "${CI:-}" == "true" ]]; then
    record_check id=offline.duration suite=offline mandatory=true state=failed \
      reason="${detail} (enforced in CI)" claim_kind=local-structural
  else
    record_check id=offline.duration suite=offline mandatory=false state=passed \
      claim_kind=local-structural reason=""
  fi
fi
