#!/usr/bin/env bash
# Generate opencode commands from the Claude Code Spec Kit skills.
#
#   .claude/skills/speckit-<name>/SKILL.md  ->  .opencode/command/speckit-<name>.md
#
# The skills are the source of truth; these commands are derived, so re-run this
# script after `specify` upgrades the skills. opencode discovers every
# `.opencode/command/**/*.md` and exposes it as `/<filename>`, with the body as
# the prompt template and `$ARGUMENTS` replaced by whatever follows the command.
# The skill bodies already contain a `## User Input` block with `$ARGUMENTS`, so
# only the front matter needs translating.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT}/.claude/skills"
OUT="${ROOT}/.opencode/command"
AGENT="${SPECKIT_OPENCODE_AGENT:-build}"

[[ -d "${SRC}" ]] || { echo "sync: no ${SRC}" >&2; exit 1; }
mkdir -p "${OUT}"

n=0
for skill in "${SRC}"/speckit-*/SKILL.md; do
  [[ -f "${skill}" ]] || continue
  dir="$(dirname "${skill}")"
  name="$(basename "${dir}")"

  # description from the skill's front matter (first block between --- lines)
  desc="$(awk '/^---$/{b++; next} b==1 && /^description:/{
            sub(/^description:[[:space:]]*/, ""); gsub(/^"|"$/, ""); print; exit }' "${skill}")"
  [[ -n "${desc}" ]] || desc="Spec Kit: ${name}"

  {
    echo "---"
    echo "description: \"${desc//\"/\\\"}\""
    echo "agent: ${AGENT}"
    echo "---"
    # body = everything after the front matter, with the Claude-specific
    # invocation hint rewritten for opencode
    awk '/^---$/{b++; if (b<=2) next} b>=2' "${skill}" \
      | sed 's|(the invocation may differ from the literal `{command}` id shown above, e.g. a skills-mode agent runs it as `/skill:speckit-...` or `\$speckit-...`)|(in opencode, run it as `/speckit-<name>`, e.g. `/speckit-plan`)|g'
  } > "${OUT}/${name}.md"
  n=$((n + 1))
  echo "  ${name}"
done
echo "sync: wrote ${n} opencode command(s) to ${OUT#"${ROOT}"/}"
