#!/usr/bin/env bash
# lib/oracle.sh — oracle integrity: digest, read-only, verify (T019, FR-015).
#
#   oracle_freeze   digest tests/e2e/oracle, chmod -R a-w for the duration.
#   oracle_verify   digest again, restore writability, compare. Any difference
#                   records check oracle.integrity=failed (exit 4 downstream).
: "${E2E_RUN_DIR:?}" "${E2E_ROOT:?}"

oracle_digest_now() {
  "${E2E_ROOT}/tools/digest.py" "${E2E_ROOT}/oracle"
}

oracle_freeze() {
  local d
  d="$(oracle_digest_now)"
  echo "${d}" > "${E2E_RUN_DIR}/oracle-digest-before.txt"
  chmod -R a-w "${E2E_ROOT}/oracle"
  if [[ -n "${E2E_WORKSPACE:-}" && -f "${E2E_WORKSPACE}/workspace.json" ]]; then
    # shellcheck disable=SC1091
    source "${E2E_ROOT}/lib/workspace.sh" 2>/dev/null || true
    workspace_update --arg d "${d}" '.oracle_digest_before = $d' || true
  fi
}

oracle_verify() {  # [suite-for-check] [mutation-id]
  local suite="${1:-live}" mutation_id="${2:-}" before after
  chmod -R u+w "${E2E_ROOT}/oracle"
  after="$(oracle_digest_now)"
  echo "${after}" > "${E2E_RUN_DIR}/oracle-digest-after.txt"
  before="$(cat "${E2E_RUN_DIR}/oracle-digest-before.txt" 2>/dev/null || echo MISSING)"
  # shellcheck disable=SC1091
  source "${E2E_ROOT}/lib/assert.sh"
  local -a rargs=(id=oracle.integrity "suite=${suite}" mandatory=true claim_kind=none)
  [[ -n "${mutation_id}" ]] && rargs+=("mutation_id=${mutation_id}")
  if [[ "${before}" != "${after}" ]]; then
    record_check "${rargs[@]}" state=failed \
      reason="oracle tree changed during run (${before} -> ${after})"
    return 1
  fi
  record_check "${rargs[@]}" state=passed
}
