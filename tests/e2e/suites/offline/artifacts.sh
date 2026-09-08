#!/usr/bin/env bash
# suites/offline/artifacts.sh — parse every generated artifact with
# tools/parse.py, validate against expected-artifacts.json, and fail on any
# unexpected file the run produced (T039, FR-037).
set -euo pipefail
E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${E2E_RUN_DIR:?}" "${E2E_WORKSPACE:?}" "${E2E_OFFLINE_DIR:?}"
# shellcheck disable=SC1091
source "${E2E_ROOT}/lib/assert.sh"

fail_reason=""
# 1. Every manifest entry exists in the workspace and parses.
while IFS= read -r rel; do
  [[ -z "${rel}" || "${rel}" == \#* ]] && continue
  if [[ ! -f "${E2E_WORKSPACE}/${rel}" ]]; then
    fail_reason="manifest entry missing from workspace: ${rel}"; break
  fi
  if ! "${E2E_ROOT}/tools/parse.py" "${E2E_WORKSPACE}/${rel}" >/dev/null 2>&1; then
    fail_reason="generated artifact does not parse: ${rel}"; break
  fi
done < "${E2E_WORKSPACE}/agent/harness-specs/loom-manifest.txt"

# 2. Every expected artifact (base variant) is present.
if [[ -z "${fail_reason}" ]]; then
  while IFS= read -r path; do
    [[ -f "${E2E_WORKSPACE}/${path}" ]] \
      || { fail_reason="expected artifact absent: ${path}"; break; }
  done < <(jq -r '.artifacts[] | select(.variants | index("base")) | .path' \
    "${E2E_ROOT}/oracle/expected-artifacts.json")
fi

# 3. No unexpected file: every manifest entry must be an expected artifact.
if [[ -z "${fail_reason}" ]]; then
  while IFS= read -r rel; do
    [[ -z "${rel}" || "${rel}" == \#* ]] && continue
    jq -e --arg p "${rel}" '.artifacts | map(.path) | index($p)' \
      "${E2E_ROOT}/oracle/expected-artifacts.json" >/dev/null \
      || { fail_reason="unexpected file produced: ${rel}"; break; }
  done < "${E2E_WORKSPACE}/agent/harness-specs/loom-manifest.txt"
fi

# 4. Manifest completeness (expect-manifest-complete).
if [[ -z "${fail_reason}" ]]; then
  while IFS= read -r entry; do
    grep -Fxq -- "${entry}" "${E2E_WORKSPACE}/agent/harness-specs/loom-manifest.txt" \
      || { fail_reason="manifest incomplete, missing: ${entry}"; break; }
  done < <(jq -r '.required_entries[]' \
    "${E2E_ROOT}/oracle/expectations/opencode/manifest.json")
fi

if [[ -z "${fail_reason}" ]]; then
  record_check id=offline.artifacts suite=offline mandatory=true state=passed \
    claim_kind=local-structural
else
  record_check id=offline.artifacts suite=offline mandatory=true state=failed \
    reason="${fail_reason}" claim_kind=local-structural
fi

# Codex/Devin structural checks, honestly labelled local-structural (T040):
# the TOML and JSON adapters must parse with stdlib parsers.
struct_reason=""
"${E2E_ROOT}/tools/parse.py" "${E2E_WORKSPACE}/.codex/config.toml" >/dev/null 2>"${E2E_OFFLINE_DIR}/structural.err" \
  || struct_reason="codex adapter does not parse: $(head -1 "${E2E_OFFLINE_DIR}/structural.err")"
for f in .devin/mcp_config.json .devin/config.json .devin/hooks.v1.json opencode.json; do
  [[ -n "${struct_reason}" ]] && break
  "${E2E_ROOT}/tools/parse.py" "${E2E_WORKSPACE}/${f}" >/dev/null 2>>"${E2E_OFFLINE_DIR}/structural.err" \
    || struct_reason="adapter does not parse: ${f}"
done
if [[ -z "${struct_reason}" ]]; then
  record_check id=offline.structural suite=offline mandatory=true state=passed \
    claim_kind=local-structural
else
  record_check id=offline.structural suite=offline mandatory=true state=failed \
    reason="${struct_reason}" claim_kind=local-structural
fi
