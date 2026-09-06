#!/usr/bin/env bash
# suites/offline/negative.sh — invalid source input, unapproved MCP name and
# endpoint, and a failing emitter that must not partially overwrite valid
# output (T044, FR-040). The four negative variants always run (fresh
# workspaces), reusing the main-loop workspace when the variant was selected.
set -euo pipefail
E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${E2E_RUN_DIR:?}" "${E2E_WORKSPACE:?}" "${E2E_OFFLINE_DIR:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/workspace.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/isolate.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/install.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/offline/materialize.sh"

# Map variant dir name -> check id suffix.
check_for() {
  case "$1" in
    negative-url-less) echo "url-less" ;;
    negative-unapproved-name) echo "unapproved-name" ;;
    negative-unapproved-endpoint) echo "unapproved-endpoint" ;;
    negative-invalid-input) echo "invalid-input" ;;
  esac
}

for variant in negative-url-less negative-unapproved-name \
               negative-unapproved-endpoint negative-invalid-input; do
  cid="offline.negative.$(check_for "${variant}")"
  pattern="$(jq -r .expected_reason_pattern \
    "${E2E_ROOT}/fixtures/variants/${variant}/manifest.json")"
  if [[ -f "${E2E_OFFLINE_DIR}/${variant}/generate-ok.txt" ]]; then
    gen_ok="$(cat "${E2E_OFFLINE_DIR}/${variant}/generate-ok.txt")"
    gen_log="$(cat "${E2E_OFFLINE_DIR}/${variant}/generate.log" 2>/dev/null || true)"
  else
    make_workspace "${E2E_ROOT}/fixtures/complete-claude"
    isolate_env
    install_loom "${E2E_WORKSPACE}" "${E2E_OFFLINE_DIR}/neg-${variant}.log" >/dev/null 2>&1
    ndir="${E2E_OFFLINE_DIR}/neg-${variant}"
    mkdir -p "${ndir}"
    materialize_variant "${variant}" "${E2E_WORKSPACE}" "${ndir}" >/dev/null 2>&1
    seed_trust "${E2E_WORKSPACE}" docs-a >/dev/null 2>&1 || true
    set +e
    gen_log="$(cd "${E2E_WORKSPACE}" && ./agent/tools/loom.sh 2>&1)"
    gen_ok=$?
    set -e
    [[ "${gen_ok}" -eq 0 ]] && gen_ok=1 || gen_ok=0
    export E2E_WORKSPACE
    E2E_WORKSPACE="$(cat "${E2E_OFFLINE_DIR}/base/workspace-path.txt")"
    export E2E_WORKSPACE
  fi
  if [[ "${gen_ok}" -eq 0 ]] && grep -Eq "${pattern}" <<<"${gen_log}"; then
    record_check id="${cid}" suite=offline mandatory=true state=passed \
      claim_kind=behaviour-probe interface="agent/tools/loom.sh"
  elif [[ "${gen_ok}" -eq 1 ]]; then
    record_check id="${cid}" suite=offline mandatory=true state=failed \
      reason="${variant}: generation succeeded but must refuse" \
      claim_kind=behaviour-probe interface="agent/tools/loom.sh"
  else
    record_check id="${cid}" suite=offline mandatory=true state=failed \
      reason="${variant}: refused but reason did not match /${pattern}/: $(grep -i error <<<"${gen_log}" | head -1)" \
      claim_kind=behaviour-probe interface="agent/tools/loom.sh"
  fi
done

# A failing emitter must not partially overwrite valid output.
P="${E2E_OFFLINE_DIR}/partial-copy"
rm -rf "${P}"
cp -a "$(cat "${E2E_OFFLINE_DIR}/base/workspace-path.txt")" "${P}"
before="$("${E2E_ROOT}/tools/digest.py" "${P}/opencode.json" "${P}/.codex" "${P}/.devin" | sha256sum | awk '{print $1}')"
# Sabotage the installed devin emitter mid-run.
printf '\nemit_devin() { echo "loom: ERROR: synthetic mid-run failure" >&2; return 1; }\n' \
  >> "${P}/agent/tools/lib/emit-devin.sh"
set +e
(cd "${P}" && ./agent/tools/loom.sh >/dev/null 2>&1)
fail_code=$?
set -e
after="$("${E2E_ROOT}/tools/digest.py" "${P}/opencode.json" "${P}/.codex" "${P}/.devin" | sha256sum | awk '{print $1}')"
rm -rf "${P}"
if [[ "${fail_code}" -ne 0 && "${before}" == "${after}" ]]; then
  record_check id=offline.negative.partial-write suite=offline mandatory=true \
    state=passed claim_kind=behaviour-probe interface="agent/tools/loom.sh"
else
  record_check id=offline.negative.partial-write suite=offline mandatory=true \
    state=failed \
    reason="mid-run emitter failure left partial output (exit ${fail_code})" \
    claim_kind=behaviour-probe interface="agent/tools/loom.sh"
fi
