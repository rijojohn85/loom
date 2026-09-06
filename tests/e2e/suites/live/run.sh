#!/usr/bin/env bash
# suites/live/run.sh — real Claude Code skill execution (T060–T069, US3).
# Installs Loom from the working checkout into an isolated workspace, invokes
# the installed skill through real Claude Code, and proves discovery and
# invocation from stream-json events plus the fixture's own hook audit log.
# Without credentials (or without the CLI) every live check reports blocked
# with the missing prerequisite named (T069, FR-047, SC-007).
set -euo pipefail

E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export E2E_ROOT
: "${E2E_RUN_DIR:?}"
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
source "${E2E_ROOT}/lib/oracle.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/evidence.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/offline/materialize.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/live/invoke.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/live/evidence.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/live/freeze.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/live/canonical.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/live/no-change.sh"
# shellcheck disable=SC1091
source "${E2E_ROOT}/suites/live/stale.sh"

LIVE_IDS="live.skill-invocation live.no-change live.schema-change live.canonical-unchanged"

if [[ "${E2E_HAVE_CLAUDE:-0}" != "1" || "${E2E_HAVE_CREDS:-0}" != "1" ]]; then
  missing="claude CLI"
  [[ "${E2E_HAVE_CLAUDE:-0}" == "1" ]] && missing="live credentials (ANTHROPIC_API_KEY or configured Claude Code login)"
  for cid in ${LIVE_IDS}; do
    record_check id="${cid}" suite=live mandatory=true state=blocked \
      reason="live layer requires ${missing}" claim_kind=none harness=claude
  done
  exit 0
fi

LIVE_DIR="${E2E_RUN_DIR}/live"
mkdir -p "${LIVE_DIR}"

make_workspace "${E2E_ROOT}/fixtures/complete-claude"
LIVE_WS="${E2E_WORKSPACE}"
# The real home holds the login; isolation hides it (see inject_claude_credentials).
REAL_HOME="${HOME}"
isolate_env
inject_claude_credentials "${REAL_HOME}"
install_loom "${LIVE_WS}" "${LIVE_DIR}/install.log" >/dev/null 2>&1 \
  || { for cid in ${LIVE_IDS}; do
         record_check id="${cid}" suite=live mandatory=true state=blocked \
           reason="workspace install failed" claim_kind=none harness=claude
       done
       exit 0; }
materialize_variant "base" "${LIVE_WS}" "${LIVE_DIR}" >/dev/null 2>&1
seed_trust "${LIVE_WS}" docs-a docs-b docs-local
# Validate the pipeline in a throwaway copy, then REMOVE the generated
# adapters from the live workspace: scenario 1 must prove the installed
# skill runs the generator itself (a model that only reads files and
# reports "all current" would prove nothing).
VALIDATE_COPY="${LIVE_DIR}/validate-copy"
rm -rf "${VALIDATE_COPY}"
cp -a "${LIVE_WS}" "${VALIDATE_COPY}"
(cd "${VALIDATE_COPY}" && ./agent/tools/loom.sh >"${LIVE_DIR}/pre-generate.log" 2>&1) \
  || { for cid in ${LIVE_IDS}; do
         record_check id="${cid}" suite=live mandatory=true state=blocked \
           reason="pipeline validation generate failed — see live/pre-generate.log" \
           claim_kind=none harness=claude
       done
       rm -rf "${VALIDATE_COPY}"
       exit 0; }
rm -rf "${VALIDATE_COPY}"
rm -rf "${LIVE_WS}/.codex" "${LIVE_WS}/.devin" "${LIVE_WS}/opencode.json" \
       "${LIVE_WS}/agent/harness-specs/GAPS.md" \
       "${LIVE_WS}/agent/harness-specs/loom-manifest.txt"

# Oracle protection around every live phase (T067, FR-032).
oracle_freeze
canonical_snapshot "${LIVE_WS}" "${LIVE_DIR}" before
{
  for p in .codex .devin opencode.json agent .claude CLAUDE.md AGENTS.md \
           .mcp.json hooks; do
    [[ -e "${LIVE_WS}/${p}" ]] && digest_manifest "${LIVE_WS}/${p}"
  done
} > "${LIVE_DIR}/live-1.before.manifest"

# Scenario 1: generate through the installed skill.
invoke_claude "${LIVE_WS}" "${E2E_ROOT}/suites/live/prompts/generate.txt" \
  "${LIVE_DIR}" "live-1"
if invoke_auth_failed "${LIVE_DIR}" "live-1"; then
  # Credentials present but rejected: every live check reports blocked with
  # the prerequisite named (Pr. VIII — never a pass, and not a code failure)
  # (T107).
  for cid in ${LIVE_IDS}; do
    record_check id="${cid}" suite=live mandatory=true state=blocked \
      reason="live layer requires working claude credentials (OAuth refresh token expired — run claude /login)" \
      claim_kind=none harness=claude
  done
  oracle_verify live || true
  exit 0
fi
{
  for p in .codex .devin opencode.json agent .claude CLAUDE.md AGENTS.md \
           .mcp.json hooks; do
    [[ -e "${LIVE_WS}/${p}" ]] && digest_manifest "${LIVE_WS}/${p}"
  done
} > "${LIVE_DIR}/live-1.after.manifest"
prove_skill_invocation "${LIVE_WS}" "${LIVE_DIR}" "live-1" "live.skill-invocation"

# Post-skill input freeze (T066).
freeze_live_inputs "${LIVE_WS}" "${LIVE_DIR}"

# Scenario 2: no-change verification (T064).
live_no_change "${LIVE_WS}" "${LIVE_DIR}"

# Scenario 3: stale pack refresh (T065).
live_stale "${LIVE_WS}" "${LIVE_DIR}"

# Canonical files unchanged (T068) and oracle intact (T067).
canonical_snapshot "${LIVE_WS}" "${LIVE_DIR}" after
canonical_verify "${LIVE_DIR}" "live.canonical-unchanged"
oracle_verify live || true
