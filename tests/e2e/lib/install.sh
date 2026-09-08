#!/usr/bin/env bash
# lib/install.sh — install Loom from the working checkout (T014, FR-020/023).
#
#   install_loom <workspace>
# Runs repo install.sh in copy mode into the workspace, verifies installed
# contents and locations, captures the source revision and a SHA-256 digest
# over the installed working-tree files (uncommitted changes included), and
# exercises reinstall preservation plus a custom --tools-dir/--skills-dir
# install into a scratch directory.
: "${REPO_ROOT:?}" "${E2E_ROOT:?}"

install_loom() {
  local ws="$1" log="$2"
  [[ -d "${ws}" ]] || { echo "install_loom: no workspace ${ws}" >&2; return 2; }
  : "${log:=/dev/null}"

  "${REPO_ROOT}/install.sh" "${ws}" >"${log}" 2>&1 || return 1
  [[ -x "${ws}/agent/tools/loom.sh" ]] || { echo "install_loom: loom.sh missing" >>"${log}"; return 1; }
  [[ -d "${ws}/agent/tools/lib" ]] || { echo "install_loom: lib/ missing" >>"${log}"; return 1; }
  [[ -f "${ws}/agent/tools/loom.config.json" ]] || { echo "install_loom: config missing" >>"${log}"; return 1; }
  [[ -f "${ws}/.claude/skills/loom/SKILL.md" ]] || { echo "install_loom: skill missing" >>"${log}"; return 1; }
  [[ -f "${ws}/agent/harness-specs/devin.md" ]] || { echo "install_loom: spec packs missing" >>"${log}"; return 1; }

  # Reinstall preservation: stamp the config, reinstall, compare.
  local before after
  before="$("${E2E_ROOT}/tools/digest.py" "${ws}/agent/tools/loom.config.json")"
  "${REPO_ROOT}/install.sh" "${ws}" >>"${log}" 2>&1 || return 1
  after="$("${E2E_ROOT}/tools/digest.py" "${ws}/agent/tools/loom.config.json")"
  [[ "${before}" == "${after}" ]] || { echo "install_loom: reinstall did not preserve config" >>"${log}"; return 1; }

  # Custom-path install into a scratch dir (FR-023).
  local scratch
  scratch="$(mktemp -d)"
  "${REPO_ROOT}/install.sh" "${scratch}" --tools-dir custom/tools \
    --skills-dir custom/skills >>"${log}" 2>&1 || { rm -rf "${scratch}"; return 1; }
  [[ -x "${scratch}/custom/tools/loom.sh" && -f "${scratch}/custom/skills/loom/SKILL.md" ]] \
    || { echo "install_loom: custom-path install misplaced files" >>"${log}"; rm -rf "${scratch}"; return 1; }
  rm -rf "${scratch}"

  {
    echo "source_revision=$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "worktree_digest=$("${E2E_ROOT}/tools/digest.py" "${REPO_ROOT}/loom.sh" "${REPO_ROOT}/lib" "${REPO_ROOT}/install.sh" "${REPO_ROOT}/skills" "${REPO_ROOT}/harness-specs" | sha256sum | awk '{print $1}')"
  } >>"${log}"
  return 0
}
