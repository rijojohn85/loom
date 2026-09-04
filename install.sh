#!/usr/bin/env bash
# Install loom into a repository.
#
#   install.sh <repo> [--tools-dir DIR] [--skills-dir DIR] [--specs-dir DIR] [--link]
#
#   --tools-dir   where loom.sh, lib/ and loom.config.json go
#                 (default: agent/tools)
#   --skills-dir  where the Claude Code skill goes (default: .claude/skills)
#   --specs-dir   where the starter spec packs go (default: agent/harness-specs);
#                 existing packs are never overwritten
#   --link        symlink loom.sh and lib/ to this checkout instead of copying
#                 (handy while developing loom itself)
#
# Re-running is safe: the tool and skill are refreshed, your config and spec
# packs are left alone.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-}"
[[ -n "${TARGET}" && -d "${TARGET}" ]] || { sed -n '2,15p' "$0"; exit 2; }
shift
TARGET="$(cd "${TARGET}" && pwd)"

TOOLS_DIR="agent/tools"
SKILLS_DIR=".claude/skills"
SPECS_DIR="agent/harness-specs"
LINK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tools-dir) TOOLS_DIR="$2"; shift ;;
    --skills-dir) SKILLS_DIR="$2"; shift ;;
    --specs-dir) SPECS_DIR="$2"; shift ;;
    --link) LINK=1 ;;
    *) echo "install.sh: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

tools="${TARGET}/${TOOLS_DIR}"
mkdir -p "${tools}/lib" "${TARGET}/${SKILLS_DIR}/loom" "${TARGET}/${SPECS_DIR}"

put() {  # put <src> <dst>
  if [[ ${LINK} -eq 1 ]]; then
    ln -sfn "$1" "$2"
  else
    rm -rf "$2"; cp -R "$1" "$2"
  fi
}
put "${SRC}/loom.sh" "${tools}/loom.sh"
put "${SRC}/lib" "${tools}/lib"
cp "${SRC}/skills/loom/SKILL.md" "${TARGET}/${SKILLS_DIR}/loom/SKILL.md"

if [[ ! -f "${tools}/loom.config.json" ]]; then
  # Start from the example, pre-filled with the layout chosen here.
  jq --arg specs "${SPECS_DIR}" --arg script "${TOOLS_DIR}/loom.sh" --arg cfg "${TOOLS_DIR}/loom.config.json" '
    .paths.spec_packs = $specs
    | .paths.loom_script = $script
    | .paths.loom_config = $cfg
    | del(.mcp_overrides.devin["_example-server-name"])
    | del(._paths_help, ._mcp_note_help, ._mcp_overrides_help)
  ' "${SRC}/loom.config.example.json" > "${tools}/loom.config.json"
  echo "wrote ${TOOLS_DIR}/loom.config.json (edit paths.mcp_allowlist, mcp_note, mcp_overrides)"
else
  echo "kept existing ${TOOLS_DIR}/loom.config.json"
fi

for pack in "${SRC}"/harness-specs/*.md; do
  name="$(basename "${pack}")"
  [[ "${name}" == "GAPS.md" ]] && continue
  if [[ -f "${TARGET}/${SPECS_DIR}/${name}" ]]; then
    echo "kept existing ${SPECS_DIR}/${name}"
  else
    cp "${pack}" "${TARGET}/${SPECS_DIR}/${name}"
  fi
done

cat <<NEXT

loom installed into ${TARGET}

Next:
  1. Edit ${TOOLS_DIR}/loom.config.json (allowlist, note, Devin overrides).
  2. Generate:      ${TOOLS_DIR}/loom.sh
  3. Gate drift in lint, e.g. in a makefile target:
         @bash ${TOOLS_DIR}/loom.sh --check
  4. Commit the generated adapters together with the config.
NEXT
