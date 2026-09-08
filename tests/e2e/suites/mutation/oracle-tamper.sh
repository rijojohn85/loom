#!/usr/bin/env bash
# suites/mutation/oracle-tamper.sh — a mutation that edits a file under
# tests/e2e/oracle/ must be refused or reported as an oracle-integrity
# failure, never absorbed (T055, FR-014, FR-015).
#
# Exercises the real protection: freeze makes the oracle read-only, the
# tamper attempt must fail with EACCES, and the post-run digest must match.
# If the write unexpectedly succeeds, the digest verification must flag it.
set -euo pipefail

E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export E2E_ROOT
: "${E2E_RUN_DIR:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/oracle.sh"

rid="mutation.oracle-tamper"
fail() {
  record_check id=mutation.oracle-tamper suite=mutation mandatory=true \
    state=failed claim_kind=local-structural mutation_id="${rid}" reason="$1"
}
pass() {
  record_check id=mutation.oracle-tamper suite=mutation mandatory=true \
    state=passed claim_kind=local-structural mutation_id="${rid}" \
    evidence="mutation/oracle-tamper.log" \
    reason="validator oracle.integrity failed as declared"
}

oracle_freeze
# The tamper: a runaway process appending to the capability inventory.
write_code=0
echo '{"tamper": true}' >> "${E2E_ROOT}/oracle/capabilities.json" 2>"${E2E_RUN_DIR}/mutation/oracle-tamper.log" \
  || write_code=1

if [[ "${write_code}" -ne 0 ]]; then
  # Refused at the filesystem layer — the preferred outcome.
  echo "tamper refused (exit ${write_code})" >> "${E2E_RUN_DIR}/mutation/oracle-tamper.log"
  if oracle_verify mutation "${rid}"; then
    pass
  else
    fail "tamper refused but post-run digest differs — tree left inconsistent"
  fi
else
  # The write landed: the digest backstop must catch it. Verify FIRST on the
  # tampered tree, restore only afterwards.
  if oracle_verify mutation "${rid}"; then
    # Verify passed despite a real change: protection is broken.
    fail "oracle write succeeded and digest verification missed it"
  else
    pass
  fi
  # Surgical restore: remove only the appended tamper line, never touch
  # anything else (the oracle may hold uncommitted reviewed work).
  if tail -1 "${E2E_ROOT}/oracle/capabilities.json" | grep -q '"tamper": true'; then
    head -n -1 "${E2E_ROOT}/oracle/capabilities.json" > "${E2E_ROOT}/oracle/capabilities.json.tmp" \
      && mv "${E2E_ROOT}/oracle/capabilities.json.tmp" "${E2E_ROOT}/oracle/capabilities.json"
  fi
  chmod -R u+w "${E2E_ROOT}/oracle"
fi
