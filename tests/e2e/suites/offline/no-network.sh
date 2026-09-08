#!/usr/bin/env bash
# suites/offline/no-network.sh — the offline layer performs zero network
# calls (T050, SC-001, FR-001). Re-runs generation plus the Python validators
# on a workspace copy with outbound access denied (unshare -n). Any attempted
# connection fails the check. Without unshare, the denial cannot be enforced
# and the check reports blocked rather than passing blind.
set -euo pipefail
E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${E2E_RUN_DIR:?}" "${E2E_OFFLINE_DIR:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"

# Deny outbound access: unshare -n (privileged), unshare -rn (unprivileged
# user+net namespace), or bwrap. Without any of the three, the denial cannot
# be enforced and the check reports blocked rather than passing blind.
NET_DENY=""
if unshare -n true 2>/dev/null; then
  NET_DENY="unshare -n"
elif unshare -rn true 2>/dev/null; then
  NET_DENY="unshare -rn"
elif bwrap --unshare-net --bind / / true 2>/dev/null; then
  NET_DENY="bwrap --unshare-net --bind / / --dev /dev --proc /proc"
else
  record_check id=offline.no-network suite=offline mandatory=true state=blocked \
    reason="neither unshare -n nor bwrap --unshare-net works here: network denial cannot be enforced" \
    claim_kind=local-structural
  exit 0
fi

NN="${E2E_OFFLINE_DIR}/nonet-copy"
rm -rf "${NN}"
cp -a "$(cat "${E2E_OFFLINE_DIR}/base/workspace-path.txt")" "${NN}"
if ${NET_DENY} bash -c "
  set -euo pipefail
  cd '${NN}' && ./agent/tools/loom.sh >/dev/null 2>&1
  '${E2E_ROOT}/tools/parse.py' '${NN}/opencode.json' >/dev/null
  '${E2E_ROOT}/tools/parse.py' '${NN}/.codex/config.toml' >/dev/null
  '${E2E_ROOT}/.venv/bin/python' '${E2E_ROOT}/tools/schema_validate.py' '${E2E_ROOT}/schemas/opencode.config.schema.json' '${NN}/opencode.json' >/dev/null
  '${E2E_ROOT}/tools/digest.py' '${NN}' >/dev/null
  '${E2E_ROOT}/tools/compare.py' '${NN}/opencode.json' '${NN}/opencode.json' >/dev/null
" >"${E2E_OFFLINE_DIR}/no-network.log" 2>&1; then
  record_check id=offline.no-network suite=offline mandatory=true state=passed \
    claim_kind=local-structural \
    interface="${NET_DENY} agent/tools/loom.sh + tools/*.py" reason=""
else
  record_check id=offline.no-network suite=offline mandatory=true state=failed \
    reason="offline tooling attempted a network call with outbound denied (see offline/no-network.log)" \
    claim_kind=local-structural
fi
rm -rf "${NN}"
