#!/usr/bin/env bash
# suites/live/canonical.sh — the workspace's canonical config files are
# unchanged after a live run unless the scenario explicitly permits a change
# (T068, FR-032). Sourced; call canonical_snapshot <ws> <evdir> <when>
# (when = before|after), then canonical_verify <evdir> <check-id>.
: "${E2E_RUN_DIR:?}" "${E2E_ROOT:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh" 2>/dev/null || true

_CANONICAL_FILES=".mcp.json .claude/settings.json CLAUDE.md AGENTS.md
  agent/policies/allowed-mcp-servers.md agent/policies/data-handling.md"

canonical_snapshot() {  # <ws> <evdir> <when>
  local ws="$1" evdir="$2" when="$3" f
  : > "${evdir}/canonical.${when}.manifest"
  for f in ${_CANONICAL_FILES}; do
    [[ -f "${ws}/${f}" ]] || { echo "MISSING ${f}" >> "${evdir}/canonical.${when}.manifest"; continue; }
    sha256sum "${ws}/${f}" | sed "s| ${ws}/|  |" >> "${evdir}/canonical.${when}.manifest"
  done
}

canonical_verify() {  # <evdir> <check-id>
  local evdir="$1" check_id="$2"
  if diff -q "${evdir}/canonical.before.manifest" "${evdir}/canonical.after.manifest" >/dev/null 2>&1; then
    record_check id="${check_id}" suite=live mandatory=true state=passed \
      claim_kind=local-structural interface="sha256 canonical manifest"
  else
    record_check id="${check_id}" suite=live mandatory=true state=failed \
      reason="canonical config changed during live run: $(diff "${evdir}/canonical.before.manifest" "${evdir}/canonical.after.manifest" | grep '^[<>]' | head -3 | tr '\n' ';')" \
      claim_kind=local-structural interface="sha256 canonical manifest"
  fi
}
