#!/usr/bin/env bash
# suites/live/evidence.sh — three-signal skill-invocation proof plus run
# metadata (T061, T062, research D4). Sourced; call:
#   prove_skill_invocation <workspace> <evidence-dir> <tag> <check-id>
# Records the named check (mandatory, behaviour-probe) itself.
#
# The three signals, all required:
# 1. A stream-json event showing the Skill tool invoked with the loom skill.
# 2. A tool-use event referencing agent/tools/loom.sh plus the generator's
#    own `loom: emitted N adapter set(s)` output.
# 3. The fixture's hook audit log in the workspace (written by the harness,
#    not the driver) proving project hooks actually ran.
: "${E2E_RUN_DIR:?}" "${E2E_ROOT:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/evidence.sh" 2>/dev/null || true

prove_skill_invocation() {
  local ws="$1" evdir="$2" tag="$3" check_id="$4"
  local stream="${evdir}/${tag}.stream-json.jsonl"
  local reason=""

  # Signal 1: Skill tool invoked with skill == loom (the tool_use input
  # shape, not a prose mention of the skill).
  if grep -Eq '"name"[ ]*:[ ]*"Skill"' "${stream}" 2>/dev/null \
    && grep -Eq '"skill"[ ]*:[ ]*"loom[^"]*"' "${stream}" 2>/dev/null; then
    :
  else
    reason="no Skill-tool event naming loom in ${tag} transcript"
  fi

  # Signal 2: a Bash tool-use whose command runs the installed generator,
  # plus the generator's EXECUTED marker (expanded adapter count — the
  # unexpanded template string appears in loom.sh source, which the model
  # legitimately reads, so only `emitted N` with a digit counts).
  if [[ -z "${reason}" ]]; then
    if grep -Eq '"command"[ ]*:[ ]*".*agent/tools/loom\.sh' "${stream}" 2>/dev/null \
      && grep -Eq 'loom: emitted [0-9]+ adapter' "${stream}" 2>/dev/null; then
      :
    else
      reason="no executed agent/tools/loom.sh invocation with generator marker in ${tag} transcript"
    fi
  fi

  # Signal 3: the fixture's own hook audit log in the workspace. The
  # generator writes adapters with cp inside Bash calls, so the proof is a
  # PostToolUse-Bash audit entry naming the generator invocation — an
  # artefact written by the harness running project hooks, not by the driver.
  if [[ -z "${reason}" ]]; then
    if [[ -f "${ws}/hooks/audit.log" ]] \
      && grep -q "PostToolUse Bash .*agent/tools/loom.sh" "${ws}/hooks/audit.log"; then
      :
    else
      reason="fixture hook audit log missing a loom.sh invocation entry in workspace"
    fi
  fi

  # Run metadata (T062): versions + changed-file set + digest manifest.
  {
    echo "claude_version=$(claude --version 2>/dev/null | head -1)"
    echo "model=$(jq -s -r '[.. | objects | .model? // empty] | last // empty' "${stream}" 2>/dev/null)"
  } > "${evdir}/${tag}.versions.txt"
  if [[ -f "${evdir}/${tag}.before.manifest" && -f "${evdir}/${tag}.after.manifest" ]]; then
    comm -13 <(sort "${evdir}/${tag}.before.manifest") \
             <(sort "${evdir}/${tag}.after.manifest") \
      > "${evdir}/${tag}.changed-files.txt" || true
  fi

  # Retain through the redaction gate (FR-026): refuse, don't write, on match.
  local ev_paths=()
  for f in "${tag}.stream-json.jsonl" "${tag}.consumption.json" \
           "${tag}.versions.txt" "${tag}.changed-files.txt"; do
    if [[ -f "${evdir}/${f}" ]]; then
      if rp="$(retain_file "${check_id}" "${evdir}/${f}" 2>/dev/null)"; then
        ev_paths+=("${rp}")
      else
        reason="redaction refused ${f} — credential pattern matched, run fails rather than retaining it"
        break
      fi
    fi
  done
  if [[ -f "${ws}/hooks/audit.log" ]]; then
    cp "${ws}/hooks/audit.log" "${evdir}/${tag}.hook-audit.log" 2>/dev/null || true
    if rp="$(retain_file "${check_id}" "${evdir}/${tag}.hook-audit.log" 2>/dev/null)"; then
      ev_paths+=("${rp}")
    fi
  fi
  local ev_csv
  ev_csv="$(IFS=,; echo "${ev_paths[*]}")"

  if [[ -z "${reason}" ]]; then
    record_check id="${check_id}" suite=live mandatory=true state=passed \
      claim_kind=behaviour-probe harness=claude \
      version="$(claude --version 2>/dev/null | awk '{print $1}')" \
      interface="claude -p --output-format stream-json" evidence="${ev_csv}"
  else
    record_check id="${check_id}" suite=live mandatory=true state=failed \
      reason="${reason}" claim_kind=behaviour-probe harness=claude \
      interface="claude -p --output-format stream-json" evidence="${ev_csv}"
  fi
}
