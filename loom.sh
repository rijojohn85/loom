#!/usr/bin/env bash

# loom - one AI-agent configuration, woven into the rest.
# Copyright (C) 2026 Rijo John
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, version 3.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public
# License along with this program. If not, see <https://www.gnu.org/licenses/>.

# loom — emit AI-harness adapter configs from one canonical Claude Code config.
#
# You maintain ONE source of truth (.mcp.json + .claude/settings.json + your
# context file); loom translates it into the config formats of the other
# harnesses (Codex, Devin, opencode, ...) deterministically: one input ->
# byte-identical output, no network, no model. `--check` diffs regeneration
# against the committed adapters and exits 1 on any drift, so adapters can
# never be hand-edited without lint noticing. When paths.manifest is
# configured, --check also flags emitted files that regeneration no longer
# produces (orphans).
#
# Anything a harness cannot express is written to GAPS.md with the
# compensating control. Silent loss is the failure mode; gaps are loud.
#
# Emitters live in lib/emit-<harness>.sh (a drop-in registry). Adding a
# harness = one emitter file + one spec pack, no core changes.
#
# Configuration: loom.config.json (see loom.config.example.json). Looked up
# via --config, $LOOM_CONFIG, next to this script, or at the repo root.

set -euo pipefail

LOOM_VERSION="0.1.0"
LOOM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
usage: loom.sh [--config FILE] [--check] [harness ...]

  (no args)        emit adapters into the repo (apply mode)
  --check          emit into a temp dir and diff against committed files;
                   exit 1 with the diff on any drift
  --config FILE    loom.config.json to use (default: $LOOM_CONFIG, then the
                   file next to loom.sh, then <repo root>/loom.config.json)
  --list           list the emitters in lib/ and exit
  --version        print the loom version and exit
  harness ...      restrict to named harness(es), e.g. `loom.sh devin`
USAGE
}

die() { echo "loom: ERROR: $*" >&2; exit 1; }

CONFIG="${LOOM_CONFIG:-}"
CHECK=0
LIST=0
HARNESSES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --version) echo "loom ${LOOM_VERSION}"; exit 0 ;;
    --check) CHECK=1 ;;
    --list) LIST=1 ;;
    --config) [[ $# -ge 2 ]] || die "--config needs a file"; CONFIG="$2"; shift ;;
    --config=*) CONFIG="${1#*=}" ;;
    -*) usage >&2; die "unknown option: $1" ;;
    *) HARNESSES+=("$1") ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || die "jq is required"

# ---------------------------------------------------------------- emitters
EMITTERS=()
collect_emitters() {
  local f name
  for f in "${LOOM_DIR}"/lib/emit-*.sh; do
    [[ -f "${f}" ]] || continue
    # shellcheck disable=SC1090
    source "${f}"
    name="$(basename "${f}" .sh)"
    name="${name#emit-}"
    if [[ ${#HARNESSES[@]} -eq 0 ]]; then
      [[ " ${EMITTERS[*]:-} " == *" ${name} "* ]] || EMITTERS+=("${name}")
    else
      for h in "${HARNESSES[@]}"; do
        [[ "${name}" == "${h}" ]] || continue
        [[ " ${EMITTERS[*]:-} " == *" ${name} "* ]] || EMITTERS+=("${name}")
      done
    fi
  done
  return 0   # the loop's last test may fail; that is not an error
}
collect_emitters
if [[ ${LIST} -eq 1 ]]; then
  printf '%s\n' "${EMITTERS[@]}"
  exit 0
fi
[[ ${#EMITTERS[@]} -gt 0 ]] || die "no emitters matched: ${HARNESSES[*]:-<all>}"

# ---------------------------------------------------------------- config
if [[ -z "${CONFIG}" ]]; then
  if [[ -f "${LOOM_DIR}/loom.config.json" ]]; then
    CONFIG="${LOOM_DIR}/loom.config.json"
  else
    _root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    [[ -f "${_root}/loom.config.json" ]] && CONFIG="${_root}/loom.config.json"
  fi
fi
[[ -n "${CONFIG}" && -f "${CONFIG}" ]] \
  || die "no loom.config.json found — copy loom.config.example.json and pass --config"
CONFIG="$(cd "$(dirname "${CONFIG}")" && pwd)/$(basename "${CONFIG}")"
CONFIG_DIR="$(dirname "${CONFIG}")"
jq -e . "${CONFIG}" >/dev/null 2>&1 || die "config is not valid JSON: ${CONFIG}"

cfg() { jq -r "$1 // empty" "${CONFIG}"; }

REPO_ROOT="$(cfg '.paths.repo_root')"
if [[ -z "${REPO_ROOT}" ]]; then
  REPO_ROOT="$(git -C "${CONFIG_DIR}" rev-parse --show-toplevel 2>/dev/null || echo "${CONFIG_DIR}")"
elif [[ "${REPO_ROOT}" != /* ]]; then
  REPO_ROOT="$(cd "${CONFIG_DIR}/${REPO_ROOT}" && pwd)"
fi

MCP_JSON="$(cfg '.paths.mcp_json')";              MCP_JSON="${MCP_JSON:-.mcp.json}"
CLAUDE_SETTINGS="$(cfg '.paths.claude_settings')"; CLAUDE_SETTINGS="${CLAUDE_SETTINGS:-.claude/settings.json}"
CONTEXT_FILE="$(cfg '.paths.canonical_context')"; CONTEXT_FILE="${CONTEXT_FILE:-AGENTS.md}"
ALLOWLIST_REL="$(cfg '.paths.mcp_allowlist')"
SPEC_PACKS_REL="$(cfg '.paths.spec_packs')"
GAPS_REL="$(cfg '.paths.gaps_file')"
[[ -z "${GAPS_REL}" && -n "${SPEC_PACKS_REL}" ]] && GAPS_REL="${SPEC_PACKS_REL}/GAPS.md"
MANIFEST_REL="$(cfg '.paths.manifest')"
MAX_AGE="$(cfg '.spec_pack_max_age_days')"; MAX_AGE="${MAX_AGE:-30}"

# Display paths for generated headers ("edit X and rerun Y").
rel_to_root() {
  local p="$1"
  case "${p}" in "${REPO_ROOT}"/*) printf '%s' "${p#"${REPO_ROOT}"/}" ;; *) printf '%s' "${p}" ;; esac
}
LOOM_SCRIPT_DISPLAY="$(cfg '.paths.loom_script')"
LOOM_SCRIPT_DISPLAY="${LOOM_SCRIPT_DISPLAY:-$(rel_to_root "${LOOM_DIR}/loom.sh")}"
CONFIG_DISPLAY="$(cfg '.paths.loom_config')"
CONFIG_DISPLAY="${CONFIG_DISPLAY:-$(rel_to_root "${CONFIG}")}"

[[ -f "${REPO_ROOT}/${MCP_JSON}" ]] || die "canonical MCP config not found: ${MCP_JSON}"
[[ -f "${REPO_ROOT}/${CLAUDE_SETTINGS}" ]] || die "canonical Claude settings not found: ${CLAUDE_SETTINGS}"

# Canonical inputs must parse and be in the shape loom supports. Fail loudly
# here rather than emit a corrupt adapter or skip the policy gate silently.
for canonical in "${REPO_ROOT}/${MCP_JSON}" "${REPO_ROOT}/${CLAUDE_SETTINGS}"; do
  jq -e . "${canonical}" >/dev/null 2>&1 \
    || die "not valid JSON: ${canonical#"${REPO_ROOT}"/}"
done
jq -e '.mcpServers | type == "object"' "${REPO_ROOT}/${MCP_JSON}" >/dev/null 2>&1 \
  || die "no mcpServers object in ${MCP_JSON}"
while IFS= read -r server; do
  [[ -n "${server}" ]] || continue
  die "MCP server '${server}' has no url in ${MCP_JSON} — loom supports url-based (http) servers only"
done < <(jq -r '.mcpServers | to_entries[]
  | select((.value.url | type) != "string" or .value.url == "") | .key' "${REPO_ROOT}/${MCP_JSON}")
[[ -f "${REPO_ROOT}/${CONTEXT_FILE}" ]] || die "canonical context file not found: ${CONTEXT_FILE}"

# ---------------------------------------------------------------- allowlist
# Hard gate: every MCP server and endpoint in the canonical config must match
# the approved policy table (a markdown table under "## Approved servers"
# with the server name in column 1 and the endpoint in column 2). Loom must
# not bypass policy by reusing an approved name for a different endpoint.
# Skipped, with a note, when no allowlist is configured.
if [[ -n "${ALLOWLIST_REL}" ]]; then
  ALLOWLIST="${REPO_ROOT}/${ALLOWLIST_REL}"
  [[ -f "${ALLOWLIST}" ]] || die "mcp_allowlist configured but not found: ${ALLOWLIST_REL}"
  while IFS=$'\t' read -r server endpoint; do
    approved_endpoint="$(awk -F '|' -v wanted="${server}" '
      /^## Approved servers/ { in_table=1; next }
      in_table && /^## / { exit }
      in_table && /^\|/ {
        name=$2; url=$3
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
        gsub(/^[[:space:]`]+|[[:space:]`]+$/, "", url)
        if (name == wanted) { print url; exit }
      }
    ' "${ALLOWLIST}")"
    [[ -n "${approved_endpoint}" ]] \
      || die "MCP server '${server}' is not approved in ${ALLOWLIST_REL}"
    [[ "${endpoint}" == "${approved_endpoint}" ]] \
      || die "MCP server '${server}' endpoint '${endpoint}' does not match approved endpoint '${approved_endpoint}'"
  done < <(jq -r '.mcpServers | to_entries[] | [.key, .value.url] | @tsv' "${REPO_ROOT}/${MCP_JSON}")
else
  echo "loom: note: no mcp_allowlist configured — endpoint policy gate skipped" >&2
fi

# ---------------------------------------------------------------- IR
# Normalize the canonical config to one intermediate representation that
# every emitter reads. Emitters never touch the source files directly.
IR="$(mktemp -d)"
trap 'rm -rf "${IR}"' EXIT

jq -n \
  --slurpfile mcp "${REPO_ROOT}/${MCP_JSON}" \
  --slurpfile settings "${REPO_ROOT}/${CLAUDE_SETTINGS}" \
  --slurpfile cfg "${CONFIG}" \
  --arg loom_script "${LOOM_SCRIPT_DISPLAY}" \
  --arg config_path "${CONFIG_DISPLAY}" \
  --arg mcp_json "${MCP_JSON}" \
  --arg claude_settings "${CLAUDE_SETTINGS}" \
  --arg allowlist "${ALLOWLIST_REL}" \
  --arg context "${CONTEXT_FILE}" \
  '
  {
    mcp: [($mcp[0].mcpServers // {}) | to_entries[] |
      { name: .key, type: .value.type, url: .value.url,
        overrides: ($cfg[0].mcp_overrides // {}) }],
    permissions: ($settings[0].permissions // {allow: []}),
    hooks: ($settings[0].hooks // {}),
    context: $context,
    meta: {
      loom_script: $loom_script,
      config_path: $config_path,
      mcp_json: $mcp_json,
      claude_settings: $claude_settings,
      allowlist: $allowlist,
      mcp_note: ($cfg[0].mcp_note // ""),
      hook_gap_control: (($cfg[0].compensating_controls.hooks
        // "git pre-commit hooks + CI running the same scripts")
        | if type == "string" then {default: .} else . end
        | if has("default") then .
          else . + {default: "git pre-commit hooks + CI running the same scripts"} end),
      permission_gap_control: (($cfg[0].compensating_controls.permissions
        // "manual approval inside the harness session")
        | if type == "string" then {default: .} else . end
        | if has("default") then .
          else . + {default: "manual approval inside the harness session"} end)
    }
  }' > "${IR}/ir.json"

# ---------------------------------------------------------------- gaps ledger
OUT="${IR}/out"
mkdir -p "${OUT}"

# The ledger is only complete when every emitter ran; a filtered run reports
# gaps on stderr and leaves the committed GAPS.md alone.
GAPS_FILE=""
if [[ -n "${GAPS_REL}" && ${#HARNESSES[@]} -eq 0 ]]; then
  GAPS_FILE="${OUT}/${GAPS_REL}"
  mkdir -p "$(dirname "${GAPS_FILE}")"
  cat > "${GAPS_FILE}" <<'GAPS'
<!-- generated by loom — do not edit by hand -->
# Harness capability gaps

Anything an emitter could not express from the IR, with the compensating
control. Empty table = the canonical config is fully representable.

| Harness | Dropped node | Compensating control |
|---------|--------------|----------------------|
GAPS
fi

gap_add() {
  # Escape pipes so a dropped node mentioning one cannot corrupt the table.
  if [[ -n "${GAPS_FILE}" ]]; then
    echo "| $1 | ${2//'|'/\\|} | ${3//'|'/\\|} |" >> "${GAPS_FILE}"
  else
    echo "loom: gap ($1): $2 — compensating control: $3" >&2
  fi
}

for h in "${EMITTERS[@]}"; do
  "emit_${h}" "${IR}/ir.json" "${OUT}"
done

# ---------------------------------------------------------------- manifest
# Records exactly which files this full run emits. --check uses the committed
# manifest to flag generated files that regeneration no longer produces
# (orphans). Maintained on full runs only, like the gaps ledger.
MANIFEST_FILE=""
if [[ -n "${MANIFEST_REL}" && ${#HARNESSES[@]} -eq 0 ]]; then
  MANIFEST_FILE="${OUT}/${MANIFEST_REL}"
  mkdir -p "$(dirname "${MANIFEST_FILE}")"
  {
    echo "# generated by loom — do not edit by hand; checked by loom.sh --check"
    (cd "${OUT}" && find . -type f -print) | sed 's|^\./||' \
      | awk -v m="${MANIFEST_REL}" '$0 != m' | LC_ALL=C sort
  } > "${MANIFEST_FILE}"
fi

# ---------------------------------------------------------------- spec-pack staleness
# Warn, never fail — refreshing a pack is a judgment call (the loom skill).
epoch_of() {
  # BSD date first: on macOS `-d` is the DST flag and would "succeed" with
  # the current time. GNU date has no -j, so it falls through to -d.
  date -j -f '%Y-%m-%d' "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null || true
}
if [[ -n "${SPEC_PACKS_REL}" && -d "${REPO_ROOT}/${SPEC_PACKS_REL}" ]]; then
  for pack in "${REPO_ROOT}/${SPEC_PACKS_REL}"/*.md; do
    [[ -f "${pack}" ]] || continue
    gen="$(awk '/^generated: /{ sub(/^generated: /, ""); print; exit }' "${pack}")"
    [[ -n "${gen}" ]] || continue
    gen_epoch="$(epoch_of "${gen}")"
    [[ -n "${gen_epoch}" ]] || continue
    age=$(( ( $(date +%s) - gen_epoch ) / 86400 ))
    if (( age > MAX_AGE )); then
      echo "loom: WARNING: spec pack ${pack##*/} is ${age} days old — run the loom skill to refresh" >&2
    fi
  done
fi

# ---------------------------------------------------------------- apply / check
# regen_manifest lists what this run emitted (same content as the generated
# manifest file, without its header); used to detect orphans.
regen_manifest() {
  (cd "${OUT}" && find . -type f -print) | sed 's|^\./||' \
    | awk -v m="${MANIFEST_REL}" '$0 != m' | LC_ALL=C sort > "${IR}/regen"
}

if [[ ${CHECK} -eq 1 ]]; then
  drift=0
  if [[ -n "${MANIFEST_REL}" && ${#HARNESSES[@]} -eq 0 && -f "${REPO_ROOT}/${MANIFEST_REL}" ]]; then
    regen_manifest
    while IFS= read -r rel; do
      [[ -z "${rel}" || "${rel}" == \#* ]] && continue
      grep -Fxq -- "${rel}" "${IR}/regen" && continue
      [[ -f "${REPO_ROOT}/${rel}" ]] || continue
      echo "loom: ORPHAN (no longer regenerated, remove by hand): ${rel}"
      drift=1
    done < "${REPO_ROOT}/${MANIFEST_REL}"
  fi
  while IFS= read -r -d '' f; do
    rel="${f#"${OUT}"/}"
    committed="${REPO_ROOT}/${rel}"
    if [[ ! -f "${committed}" ]]; then
      echo "loom: MISSING (not committed): ${rel}"
      drift=1
    elif ! diff -u "${committed}" "${f}" > "${IR}/diff"; then
      echo "loom: DRIFT in ${rel}:"; cat "${IR}/diff"
      drift=1
    fi
  done < <(find "${OUT}" -type f -print0)
  if [[ ${drift} -eq 1 ]]; then
    echo "loom: --check FAILED — regenerate with: ${LOOM_SCRIPT_DISPLAY}" >&2
    exit 1
  fi
  echo "loom: check clean — adapters match regeneration"
  exit 0
fi

# Apply: warn (never delete) about committed generated files that this
# regeneration no longer produces.
if [[ -n "${MANIFEST_REL}" && ${#HARNESSES[@]} -eq 0 && -f "${REPO_ROOT}/${MANIFEST_REL}" ]]; then
  regen_manifest
  while IFS= read -r rel; do
    [[ -z "${rel}" || "${rel}" == \#* ]] && continue
    grep -Fxq -- "${rel}" "${IR}/regen" && continue
    [[ -f "${REPO_ROOT}/${rel}" ]] \
      && echo "loom: note: orphaned generated file (no longer regenerated, left in place): ${rel}" >&2
  done < "${REPO_ROOT}/${MANIFEST_REL}"
fi

while IFS= read -r -d '' f; do
  rel="${f#"${OUT}"/}"
  mkdir -p "${REPO_ROOT}/$(dirname "${rel}")"
  cp "${f}" "${REPO_ROOT}/${rel}"
done < <(find "${OUT}" -type f -print0)
echo "loom: emitted ${#EMITTERS[@]} adapter set(s)${GAPS_FILE:+ + ${GAPS_REL}}${MANIFEST_FILE:+ + manifest}"
