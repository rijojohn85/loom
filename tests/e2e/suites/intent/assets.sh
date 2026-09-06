#!/usr/bin/env bash
# suites/intent/assets.sh — the oracle's skill/agent gap dispositions agree
# with what opencode natively lists (T092, FR-012a). For each fixture asset,
# the observed native presence must equal the oracle's native_equivalent
# entry; drift in either direction fails with an oracle-stale finding.
# Usage: <ws> <evdir>
set -euo pipefail
E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${E2E_RUN_DIR:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/evidence.sh"

WS="$1"; EVDIR="$2"
# shellcheck disable=SC1091
source "${E2E_ROOT}/probes/opencode.sh"

ev=""
if [[ "${E2E_HAVE_OPENCODE:-0}" != "1" ]]; then
  record_check id=intent.assets-gaps suite=intent mandatory=true state=blocked \
    reason="opencode CLI absent — gap dispositions unverified here" \
    claim_kind=local-structural harness=opencode
  exit 0
fi

skills="$(cd "${WS}" && run_isolated opencode debug skill 2>&1 || true)"
agents="$(cd "${WS}" && run_isolated opencode agent list 2>&1 || true)"
printf '%s' "${skills}" > "${EVDIR}/assets.skills.txt"
printf '%s' "${agents}" > "${EVDIR}/assets.agents.txt"
if rp="$(retain_file intent.assets-gaps "${EVDIR}/assets.skills.txt" assets.skills.txt 2>/dev/null)"; then
  ev="${rp}"
fi
if rp="$(retain_file intent.assets-gaps "${EVDIR}/assets.agents.txt" assets.agents.txt 2>/dev/null)"; then
  ev="${ev},${rp}"
fi

mismatch=""
for spec in "skill.lint-review:lint-review:skills" "skill.docs-sync:docs-sync:skills" \
            "agent.planner:planner:agents" "agent.reviewer:reviewer:agents"; do
  cap="${spec%%:*}"; rest="${spec#*:}"; name="${rest%%:*}"; which="${rest##*:}"
  if [[ "${which}" == "skills" ]]; then hay="${EVDIR}/assets.skills.txt";
  else hay="${EVDIR}/assets.agents.txt"; fi
  observed="false"
  grep -qi "${name}" "${hay}" 2>/dev/null && observed="true"
  expected="$(jq -r --arg g "gap.${cap}.opencode" \
    '.gaps[] | select(.gap_id == $g) | .native_equivalent.exists' \
    "${E2E_ROOT}/oracle/approved-gaps.json")"
  if [[ "${observed}" != "${expected}" ]]; then
    mismatch="oracle stale for ${cap}: observed native=${observed}, oracle says ${expected} — re-review the gap"
    break
  fi
done

if [[ -z "${mismatch}" ]]; then
  record_check id=intent.assets-gaps suite=intent mandatory=true state=passed \
    claim_kind=local-structural harness=opencode \
    interface="opencode debug skill + agent list" "evidence=${ev}" \
    reason="gap dispositions agree with native listings (skills discovered, agents absent)"
else
  record_check id=intent.assets-gaps suite=intent mandatory=true state=failed \
    reason="${mismatch}" claim_kind=local-structural harness=opencode \
    "evidence=${ev}"
fi
