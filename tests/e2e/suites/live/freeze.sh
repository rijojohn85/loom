#!/usr/bin/env bash
# suites/live/freeze.sh — freeze the post-skill tool and input snapshot into
# resolved-input.json before repeat-generation checks (T066, FR-031), so a
# mid-run tool change cannot read as nondeterminism. Sourced.
: "${E2E_RUN_DIR:?}" "${E2E_ROOT:?}"

freeze_live_inputs() {  # <workspace> <evidence-dir>
  local ws="$1" evdir="$2"
  jq -n \
    --arg fixture_rev "$("${E2E_ROOT}/tools/digest.py" "${E2E_ROOT}/fixtures")" \
    --arg cfg_digest "$("${E2E_ROOT}/tools/digest.py" "${ws}/agent/tools/loom.config.json")" \
    --arg tool_digest "$("${E2E_ROOT}/tools/digest.py" "${ws}/agent/tools/loom.sh" "${ws}/agent/tools/lib" | sha256sum | awk '{print $1}')" \
    --arg claude_ver "$(claude --version 2>/dev/null | head -1)" \
    --arg src_rev "$(git -C "${E2E_ROOT}/../.." rev-parse HEAD 2>/dev/null || echo unknown)" \
    --arg model "$(jq -s -r '[.. | objects | .model? // empty] | last // empty' "${evdir}/live-1.stream-json.jsonl" 2>/dev/null || true)" \
    '{fixture_revision: $fixture_rev, loom_config_digest: $cfg_digest,
      installed_tool_digest: $tool_digest, claude_version: $claude_ver,
      source_revision: $src_rev, model: $model,
      ephemeral_fields: {}}' > "${evdir}/resolved-input.json"
  if [[ "${evdir}/resolved-input.json" != "${E2E_RUN_DIR}/resolved-input.json" ]]; then
    cp "${evdir}/resolved-input.json" "${E2E_RUN_DIR}/resolved-input.json"
  fi
}
