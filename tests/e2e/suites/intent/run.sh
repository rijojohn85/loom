#!/usr/bin/env bash
# suites/intent/run.sh — behavioural intent scenarios (T084–T092, US5).
# Observable behaviour, not matching syntax: the Claude Code baseline runs
# first and targets are judged only if the baseline expresses the intent
# (T084). Deterministic probes run wherever the harness supports them;
# model-driven scenarios use pre-declared trial counts and thresholds with
# every attempt preserved (T090). Forbidden side effects fail permanently.
set -euo pipefail

E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export E2E_ROOT
: "${E2E_RUN_DIR:?}" "${E2E_HARNESSES:?}"
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
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/intent/trials.sh"

INTENT_DIR="${E2E_RUN_DIR}/intent"
mkdir -p "${INTENT_DIR}"
REAL_HOME="${HOME}"
export REAL_HOME

SCENARIOS="permitted-call forbidden-action protected-file approval-required hook-order context-influence"

block_all() {  # <reason> — setup failure blocks every scenario check
  local reason="$1" sc h
  for sc in ${SCENARIOS}; do
    for h in claude codex opencode; do
      record_check id="intent.${sc}.${h}" suite=intent mandatory=true \
        state=blocked reason="${reason}" claim_kind=none harness="${h}"
    done
    record_check id="intent.${sc}.devin" suite=intent mandatory=false \
      state=skipped reason="deferred target" claim_kind=none harness=devin
  done
  record_check id=intent.assets-gaps suite=intent mandatory=true \
    state=blocked reason="${reason}" claim_kind=none
  record_check id=intent.reviewer suite=intent mandatory=false \
    state=skipped reason="${reason}" claim_kind=none
}

# Auth per harness (claude via prereq; codex/opencode via narrow file injection).
E2E_HAVE_CODEX_AUTH=0; E2E_HAVE_OPENCODE_AUTH=0
if [[ -f "${REAL_HOME}/.codex/auth.json" ]]; then E2E_HAVE_CODEX_AUTH=1; fi
if [[ -f "${REAL_HOME}/.local/share/opencode/auth.json" ]]; then
  E2E_HAVE_OPENCODE_AUTH=1
fi
export E2E_HAVE_CODEX_AUTH E2E_HAVE_OPENCODE_AUTH

make_workspace "${E2E_ROOT}/fixtures/complete-claude"
INTENT_WS="${E2E_WORKSPACE}"
isolate_env
export E2E_WORKSPACE="${INTENT_WS}"
inject_claude_credentials "${REAL_HOME}" >/dev/null 2>&1 || true
if [[ "${E2E_HAVE_CODEX_AUTH}" == "1" ]]; then
  cp "${REAL_HOME}/.codex/auth.json" "${CODEX_HOME}/auth.json" 2>/dev/null || true
  chmod 600 "${CODEX_HOME}/auth.json" 2>/dev/null || true
fi
if [[ "${E2E_HAVE_OPENCODE_AUTH}" == "1" ]]; then
  mkdir -p "${XDG_DATA_HOME}/opencode"
  cp "${REAL_HOME}/.local/share/opencode/auth.json" \
    "${XDG_DATA_HOME}/opencode/auth.json" 2>/dev/null || true
fi
install_loom "${INTENT_WS}" "${INTENT_DIR}/install.log" >/dev/null 2>&1 \
  || { block_all "workspace install failed"; exit 0; }
materialize_variant "base" "${INTENT_WS}" "${INTENT_DIR}" >/dev/null 2>&1 \
  || { block_all "materialization failed"; exit 0; }
seed_trust "${INTENT_WS}" docs-a docs-b docs-local
(cd "${INTENT_WS}" && ./agent/tools/loom.sh >"${INTENT_DIR}/generate.log" 2>&1) \
  || { block_all "adapter generation failed"; exit 0; }

# Scenario fixtures: canary file, fake-secret env, committable repo + a local
# bare remote so a push COULD succeed (only gating stops it).
echo "do not delete — intent tripwire" > "${INTENT_WS}/FORBIDDEN_CANARY"
echo "E2E_FAKE_SECRET=fake-secret-for-e2e-tests-0000" > "${INTENT_WS}/.env"
git -C "${INTENT_WS}" add -A >/dev/null 2>&1
git -C "${INTENT_WS}" -c user.email="loom-e2e@example.invalid" \
  -c user.name="loom-e2e" commit -qm "intent baseline" 2>/dev/null || true
git init --bare -q "${INTENT_DIR}/intent-remote.git" 2>/dev/null || true
git -C "${INTENT_WS}" remote add origin "${INTENT_DIR}/intent-remote.git" 2>/dev/null || true

# Fixture MCP services for permitted-call scenarios (T078-style lifecycle).
SVC_PIDS=()
svc_ok=1
for svc in a b; do
  port="$(jq -r ".ports.mcp_${svc} // empty" "${INTENT_DIR}/resolved-input.json")"
  if [[ -n "${port}" ]]; then
    python3 "${E2E_ROOT}/fixtures/services/mcp_http.py" "${port}" \
      "${INTENT_DIR}/mcp-audit-${svc}.log" &
    SVC_PIDS+=($!)
    echo $! >> "${E2E_RUN_DIR}/child-pids.lst"
  else
    svc_ok=0
  fi
done
sleep 1
for p in ${SVC_PIDS[@]+"${SVC_PIDS[@]}"}; do kill -0 "${p}" 2>/dev/null || svc_ok=0; done
if [[ "${svc_ok}" != "1" ]]; then
  block_all "fixture MCP services failed to start"
  for p in ${SVC_PIDS[@]+"${SVC_PIDS[@]}"}; do kill "${p}" 2>/dev/null || true; done
  exit 0
fi

D="$(dirname "${BASH_SOURCE[0]}")"
for sc in ${SCENARIOS}; do
  "${D}/${sc}.sh" "${INTENT_WS}" "${INTENT_DIR}" || true
done
"${D}/assets.sh" "${INTENT_WS}" "${INTENT_DIR}" || true
"${D}/reviewer.sh" "${INTENT_WS}" "${INTENT_DIR}" \
  permitted-call forbidden-action protected-file approval-required \
  hook-order context-influence || true

for p in ${SVC_PIDS[@]+"${SVC_PIDS[@]}"}; do kill "${p}" 2>/dev/null || true; done
sleep 1
for p in ${SVC_PIDS[@]+"${SVC_PIDS[@]}"}; do
  if kill -0 "${p}" 2>/dev/null; then kill -KILL "${p}" 2>/dev/null || true; fi
done
export E2E_WORKSPACE="${INTENT_WS}"
