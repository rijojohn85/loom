#!/usr/bin/env bash
# End-to-end smoke test: builds a throwaway repo, installs loom into it,
# generates adapters, and checks the drift gate, the allowlist gate, the
# hook translation and the gaps ledger. No network.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
[[ -n "${KEEP:-}" ]] && echo "fixture: ${T}" || trap 'rm -rf "${T}"' EXIT
fail=0
ok()   { echo "  ok   $1"; }
bad()  { echo "  FAIL $1"; fail=1; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# ---- fixture repo
cd "${T}"
git init -q .
mkdir -p .claude agent/policies
cat > .mcp.json <<'J'
{ "mcpServers": {
    "docs-a": { "type": "http", "url": "https://a.example/mcp" },
    "docs-b": { "type": "http", "url": "https://b.example/mcp" } } }
J
cat > .claude/settings.json <<'J'
{ "permissions": { "allow": ["Bash(make lint)", "mcp__docs-a__*", "mcp__docs-b__*"] },
  "hooks": {
    "PreToolUse":  [{ "matcher": "Write|Edit", "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/hooks/pre.sh" }] }],
    "PostToolUse": [{ "matcher": "Write|Edit", "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/hooks/post.sh" }] }] } }
J
cat > agent/policies/allowed-mcp-servers.md <<'M'
# Allowed MCP servers

## Approved servers

| Server | Endpoint | Access |
|--------|----------|--------|
| docs-a | `https://a.example/mcp` | read-only |
| docs-b | `https://b.example/mcp` | read-only |

## Something else
M
echo "# AGENTS" > AGENTS.md

# ---- install
echo "install"
"${SRC}/install.sh" "${T}" >/dev/null
check "tool installed"        '[[ -x agent/tools/loom.sh && -f agent/tools/lib/emit-devin.sh ]]'
check "skill installed"       '[[ -f .claude/skills/loom/SKILL.md ]]'
check "config written"        '[[ -f agent/tools/loom.config.json ]]'
check "spec packs seeded"     '[[ -f agent/harness-specs/devin.md ]]'
jq '.paths.mcp_allowlist = "agent/policies/allowed-mcp-servers.md"
    | .mcp_overrides.devin["docs-b"] = {command: "npx", args: ["-y", "mcp-remote@0.8.3", "{{url}}"]}
    | .mcp_note = "Read-only docs servers."' \
  agent/tools/loom.config.json > c.json && mv c.json agent/tools/loom.config.json

# ---- generate
echo "generate"
out="$(agent/tools/loom.sh 2>&1)"; rc=$?
check "apply exits 0"         '[[ ${rc} -eq 0 ]]'
check "codex config"          'grep -q "^\[mcp_servers.docs-a\]" .codex/config.toml'
check "codex header note"     'grep -q "^# Read-only docs servers." .codex/config.toml'
check "codex header script"   'grep -q "re-run agent/tools/loom.sh" .codex/config.toml'
check "opencode config"       '[[ "$(jq -r .mcp[\"docs-b\"].url opencode.json)" == "https://b.example/mcp" ]]'
check "devin native transport" '[[ "$(jq -r .mcpServers[\"docs-a\"].transport .devin/mcp_config.json)" == "http" ]]'
check "devin bridge override" '[[ "$(jq -r .mcpServers[\"docs-b\"].args[2] .devin/mcp_config.json)" == "https://b.example/mcp" ]]'
check "devin mcp permissions only" '[[ "$(jq -r ".permissions.allow|length" .devin/config.json)" == "2" ]]'
check "devin PreToolUse hook"  '[[ "$(jq -r .PreToolUse[0].hooks[0].command .devin/hooks.v1.json)" == "\$DEVIN_PROJECT_DIR/hooks/pre.sh" ]]'
check "devin PostToolUse hook" 'jq -e .PostToolUse[0] .devin/hooks.v1.json >/dev/null'
check "gaps: codex hooks"      'grep -q "| codex | hook event: PreToolUse |" agent/harness-specs/GAPS.md'
check "gaps: opencode hooks"   'grep -q "| opencode | hook event: PostToolUse |" agent/harness-specs/GAPS.md'
check "gaps: devin permission" 'grep -q "| devin | permission allow: Bash(make lint) |" agent/harness-specs/GAPS.md'

# ---- drift gate
echo "drift gate"
check "check clean after apply" 'agent/tools/loom.sh --check >/dev/null 2>&1'
cp opencode.json opencode.json.bak
jq '.mcp["docs-a"].url = "https://evil.example"' opencode.json.bak > opencode.json
check "check fails on hand edit" '! agent/tools/loom.sh --check >/dev/null 2>&1'
mv opencode.json.bak opencode.json
check "check clean again"       'agent/tools/loom.sh --check >/dev/null 2>&1'
check "single harness filter"   'agent/tools/loom.sh --check devin >/dev/null 2>&1'
check "--list shows emitters"   '[[ "$(agent/tools/loom.sh --list | tr "\n" " ")" == "codex devin opencode " ]]'

# ---- allowlist gate
echo "allowlist gate"
cp .mcp.json .mcp.json.bak
jq '.mcpServers["docs-c"] = {type: "http", url: "https://c.example/mcp"}' .mcp.json.bak > .mcp.json
check "unapproved server refused" '! agent/tools/loom.sh --check >/dev/null 2>&1'
jq '.mcpServers["docs-a"].url = "https://a.example/other"' .mcp.json.bak > .mcp.json
check "wrong endpoint refused"    '! agent/tools/loom.sh --check >/dev/null 2>&1'
mv .mcp.json.bak .mcp.json

# ---- staleness warning
echo "staleness"
sed -i.bak 's/^generated: .*/generated: 2020-01-01/' agent/harness-specs/devin.md && rm -f agent/harness-specs/devin.md.bak
stale_out="$(agent/tools/loom.sh --check 2>&1 || true)"
check "stale pack warns"  '[[ "${stale_out}" == *"devin.md is "*"days old"* ]]'

# ---- re-install keeps config
echo "re-install"
"${SRC}/install.sh" "${T}" >/dev/null
check "config preserved on re-install" '[[ "$(jq -r .mcp_note agent/tools/loom.config.json)" == "Read-only docs servers." ]]'

echo
if [[ ${fail} -eq 0 ]]; then echo "smoke: all checks passed"; else echo "smoke: FAILURES"; exit 1; fi
