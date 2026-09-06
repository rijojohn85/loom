#!/usr/bin/env bash
# suites/mutation/partial-write.sh — force a lib/emit-*.sh failure mid-run
# and assert no valid artifact was left partially written (T057, FR-040).
# Unlike offline.negative.partial-write (devin emitter), this case kills the
# codex emitter after it has already written a partial file: the committed
# adapters must be byte-identical afterwards, because loom assembles output
# in a temp dir and only copies on full success.
set -euo pipefail

E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export E2E_ROOT
: "${E2E_RUN_DIR:?}" "${GOLDEN_WS:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"

rid="mutation.partial-overwrite"
P="${E2E_RUN_DIR}/mutation/ws-partial"
rm -rf "${P}"
cp -a "${GOLDEN_WS}" "${P}"
before="$("${E2E_ROOT}/tools/digest.py" "${P}/opencode.json" "${P}/.codex" "${P}/.devin" | sha256sum | awk '{print $1}')"

# Sabotage: codex emitter writes a partial file, then dies.
# (loom assembles in a temp dir, so the partial file never reaches the repo.)
printf '\nemit_codex() {\n  local ir="$1" out="$2"\n  echo "# PARTIAL" > "${out}/.codex/config.toml"\n  echo "loom: ERROR: synthetic mid-run failure" >&2\n  return 1\n}\n' >> "${P}/agent/tools/lib/emit-codex.sh"

set +e
(cd "${P}" && ./agent/tools/loom.sh >/dev/null 2>&1)
fail_code=$?
set -e
after="$("${E2E_ROOT}/tools/digest.py" "${P}/opencode.json" "${P}/.codex" "${P}/.devin" | sha256sum | awk '{print $1}')"
rm -rf "${P}"

if [[ "${fail_code}" -ne 0 && "${before}" == "${after}" ]]; then
  record_check id=mutation.partial-overwrite suite=mutation mandatory=true \
    state=passed claim_kind=behaviour-probe mutation_id="${rid}" \
    reason="validator offline.negative.partial-write failed as declared"
else
  record_check id=mutation.partial-overwrite suite=mutation mandatory=true \
    state=failed claim_kind=behaviour-probe mutation_id="${rid}" \
    reason="mid-run emitter failure left partial output (exit ${fail_code})"
fi
