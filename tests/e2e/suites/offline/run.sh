#!/usr/bin/env bash
# suites/offline/run.sh — deterministic offline gate driver (T037, T047).
# Creates the workspace, installs Loom, generates adapters, freezes
# resolved-input.json, then runs every offline check script. Suite selection
# and verdict computation belong to tests/e2e/run.sh; this driver only runs
# checks and records them via lib/assert.sh.
set -euo pipefail

E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export E2E_ROOT
: "${E2E_RUN_DIR:?}" "${E2E_SUITES:?}"
REPO_ROOT="$(cd "${E2E_ROOT}/../.." && pwd)"
export REPO_ROOT

# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/workspace.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/isolate.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/trust.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/install.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/offline/materialize.sh"

OFFLINE_DIR="${E2E_RUN_DIR}/offline"
mkdir -p "${OFFLINE_DIR}"
date +%s > "${E2E_RUN_DIR}/offline-started-at"

IFS=',' read -ra VARIANTS <<< "${E2E_VARIANTS:-base}"

# ---- one workspace per variant: install, materialize, generate
for variant in "${VARIANTS[@]}"; do
  vdir="${OFFLINE_DIR}/${variant}"
  mkdir -p "${vdir}"
  if [[ "${variant}" != "base" && ! -d "${E2E_ROOT}/fixtures/variants/${variant}" ]]; then
    record_check id="offline.variant.${variant}" suite=offline mandatory=true \
      state=failed reason="unknown variant ${variant}" claim_kind=none
    continue
  fi
  make_workspace "${E2E_ROOT}/fixtures/complete-claude"
  echo "${E2E_WORKSPACE}" > "${vdir}/workspace-path.txt"
  isolate_env
  if ! install_loom "${E2E_WORKSPACE}" "${vdir}/install.log" 2>"${vdir}/install.err"; then
    record_check id="offline.install.${variant}" suite=offline mandatory=true \
      state=failed reason="install.sh failed: $(tail -2 "${vdir}/install.err" | head -1)" \
      claim_kind=none evidence="offline/${variant}/install.log"
    continue
  fi
  record_check id="offline.install.${variant}" suite=offline mandatory=true \
    state=passed claim_kind=local-structural evidence="offline/${variant}/install.log"
  if ! materialize_variant "${variant}" "${E2E_WORKSPACE}" "${vdir}" 2>"${vdir}/materialize.err"; then
    record_check id="offline.materialize.${variant}" suite=offline mandatory=true \
      state=failed reason="materialization failed: $(cat "${vdir}/materialize.err" | head -1)" claim_kind=none
    continue
  fi
  # Trust seeding (records itself into workspace.json; skipped with --no-trust-seed).
  seed_trust "${E2E_WORKSPACE}" docs-a docs-b docs-local
  (cd "${E2E_WORKSPACE}" && ./agent/tools/loom.sh >"${vdir}/generate.log" 2>&1) \
    && gen_ok=1 || gen_ok=0
  echo "${gen_ok}" > "${vdir}/generate-ok.txt"
  cp "${vdir}/generate.log" "${vdir}/generate.log" 2>/dev/null || true
done

# The base workspace anchors every artifact-level check below.
if [[ ! -f "${OFFLINE_DIR}/base/workspace-path.txt" ]]; then
  record_check id=offline.base suite=offline mandatory=true state=failed \
    reason="base variant was not materialized — artifact checks have no anchor" \
    claim_kind=none
  exit 0
fi
BASE_WS="$(cat "${OFFLINE_DIR}/base/workspace-path.txt" 2>/dev/null || echo "")"
export E2E_WORKSPACE="${BASE_WS}"
export E2E_OFFLINE_DIR="${OFFLINE_DIR}"

# Re-enter isolation paths (subshell-safe): home dirs live under the run dir.
if [[ -d "${E2E_RUN_DIR}/home" ]]; then
  export HOME="${E2E_RUN_DIR}/home"
  export XDG_CONFIG_HOME="${E2E_RUN_DIR}/home/config"
  export XDG_DATA_HOME="${E2E_RUN_DIR}/home/data"
  export XDG_CACHE_HOME="${E2E_RUN_DIR}/home/cache"
  export CODEX_HOME="${E2E_RUN_DIR}/home/codex"
  export CLAUDE_CONFIG_DIR="${E2E_RUN_DIR}/home/claude"
fi

D="$(dirname "${BASH_SOURCE[0]}")"
for step in smoke artifacts schema idempotence portability drift negative \
            capabilities variants duration no-network verdict docs; do
  s="${D}/${step}.sh"
  [[ -x "${s}" ]] || { echo "offline: missing step ${s}" >&2; continue; }
  "${s}" || true   # steps record their own checks; a crash must not lose the run
done
