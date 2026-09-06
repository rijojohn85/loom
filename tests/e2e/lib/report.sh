#!/usr/bin/env bash
# lib/report.sh — render report.md from results.json (FR-056).
# Capability ids mapped to assertions, versions, evidence paths, and separate
# totals for passed / failed / approved-gap / skipped / blocked.
# Env in: E2E_RUN_DIR. Writes $E2E_RUN_DIR/report.md.
set -euo pipefail
: "${E2E_RUN_DIR:?}"
R="${E2E_RUN_DIR}/results.json"
OUT="${E2E_RUN_DIR}/report.md"
[[ -f "${R}" ]] || { echo "report.sh: ${R} not found" >&2; exit 2; }

{
  echo "# Loom e2e report — $(jq -r .run_id "${R}")"
  echo
  echo "- mode: $(jq -r .mode "${R}")"
  echo "- verdict: $(jq -r .verdict "${R}")"
  if jq -e .verdict_note "${R}" >/dev/null 2>&1; then
    echo "- note: $(jq -r .verdict_note "${R}")"
  fi
  echo "- inventory: $(jq -r .inventory_version "${R}")"
  echo "- suites: $(jq -r '.suites_selected | join(", ")' "${R}")"
  echo "- harnesses: $(jq -r '.harnesses_selected | join(", ")' "${R}")"
  echo "- source revision: $(jq -r .pins.source_revision "${R}")"
  echo "- worktree digest: $(jq -r .pins.worktree_digest "${R}")"
  echo
  echo "## Checks"
  echo
  echo "| Check | Suite | Mandatory | State | Claim | Harness | Observed version | Evidence |"
  echo "|---|---|---|---|---|---|---|---|"
  jq -r '.checks[] | "| \(.id) | \(.suite) | \(.mandatory) | \(.state) | \(.claim_kind) | \(.harness // "—") | \(.harness_version_observed // "—") | \((.evidence // []) | join("; ")) |"' "${R}"
  echo
  echo "## Capability outcomes"
  echo
  echo "| Capability | Harness | State | Gap | Evidence | Checks |"
  echo "|---|---|---|---|---|---|"
  jq -r '.capabilities[] | "| \(.capability_id) | \(.harness) | \(.state) | \(.gap_id // "—") | \((.evidence // []) | join("; ")) | \((.checks // []) | join(", ")) |"' "${R}"
  echo
  echo "## Totals"
  echo
  jq -r '"- checks: " + "\(.summary.checks.passed) passed · \(.summary.checks.failed) failed · \(.summary.checks.approved_gap) approved-gap · \(.summary.checks.blocked) blocked · \(.summary.checks.skipped) skipped" +
    "\n- capabilities: " + "\(.summary.capabilities.preserved) preserved · \(.summary.capabilities.verified_compensated) verified-compensated · \(.summary.capabilities.approved_gap) approved-gap · \(.summary.capabilities.failed) failed · \(.summary.capabilities.unverified) unverified" +
    (if (.summary.mandatory_not_run | length) > 0 then "\n- mandatory not run: " + (.summary.mandatory_not_run | join(", ")) else "" end)' "${R}"
} > "${OUT}"
echo "report: ${OUT}"
