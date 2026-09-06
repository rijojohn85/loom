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
usage() {
  cat <<'USAGE'
usage: install.sh <repo> [--tools-dir DIR] [--skills-dir DIR] [--specs-dir DIR] [--link]

  --tools-dir   where loom.sh, lib/ and loom.config.json go (default: agent/tools)
  --skills-dir  where the Claude Code skill goes (default: .claude/skills)
  --specs-dir   where the starter spec packs go (default: agent/harness-specs);
                existing packs are never overwritten
  --link        symlink loom.sh and lib/ to this checkout instead of copying
                (handy while developing loom itself)
USAGE
}

TARGET="${1:-}"
[[ -n "${TARGET}" && -d "${TARGET}" ]] || { usage >&2; exit 2; }
shift
TARGET="$(cd "${TARGET}" && pwd)"

TOOLS_DIR="agent/tools"
SKILLS_DIR=".claude/skills"
SPECS_DIR="agent/harness-specs"
LINK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tools-dir) [[ $# -ge 2 ]] || { echo "install.sh: --tools-dir needs a value" >&2; exit 2; }
                 TOOLS_DIR="$2"; shift ;;
    --skills-dir) [[ $# -ge 2 ]] || { echo "install.sh: --skills-dir needs a value" >&2; exit 2; }
                 SKILLS_DIR="$2"; shift ;;
    --specs-dir)  [[ $# -ge 2 ]] || { echo "install.sh: --specs-dir needs a value" >&2; exit 2; }
                 SPECS_DIR="$2"; shift ;;
    --link) LINK=1 ;;
    *) echo "install.sh: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

tools="${TARGET}/${TOOLS_DIR}"
mkdir -p "${tools}" "${TARGET}/${SKILLS_DIR}/loom" "${TARGET}/${SPECS_DIR}"

put() {  # put <src> <dst>
  if [[ ${LINK} -eq 1 ]]; then
    # A real directory at the destination would make `ln -sfn` link *into*
    # it (tools/lib/lib) instead of replacing it — remove such a dir first.
    [[ ! -d "$2" || -L "$2" ]] || rm -rf "$2"
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
    | .paths.manifest = ($specs + "/loom-manifest.txt")
    | .paths.loom_script = $script
    | .paths.loom_config = $cfg
    | del(.mcp_overrides.devin["_example-server-name"])
    | del(._comment, ._paths_help, ._mcp_note_help, ._mcp_overrides_help)
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
