# loom

Keep **one** AI-agent configuration and weave the rest from it.

If your repo is used with more than one coding agent (Claude Code, Codex,
Devin, opencode), each wants the same facts in its own file format: which
MCP servers to load, which tools are pre-approved, which hooks to run,
which context file to read. Maintaining four copies by hand means they
drift, and a drifted copy is a policy hole nobody notices.

Loom makes the Claude Code configuration the single source of truth and
generates the others from it:

```
.mcp.json  +  .claude/settings.json  +  AGENTS.md          (you edit these)
        │
        ▼  loom.sh  (deterministic, no network, no model)
        │
        ├── .codex/config.toml
        ├── .devin/{mcp_config,config,hooks.v1}.json
        ├── opencode.json
        └── GAPS.md   ← what a harness cannot express, and what covers it
```

Three properties make it safe to rely on:

- **Deterministic.** Same input, byte-identical output. No LLM, no
  network. It is a jq-and-bash program you can read in ten minutes.
- **Drift-gated.** `loom.sh --check` regenerates into a temp dir and diffs
  against what is committed. Put it in your lint target and a hand-edited
  adapter turns CI red.
- **Loud about loss.** Anything the canonical config says that a harness
  cannot represent (Codex has no hooks, opencode has no per-tool allowlist)
  is written to `GAPS.md` with the compensating control, so the gap is a
  reviewed fact rather than a silent omission.

There is one more gate, optional but recommended: if you keep an MCP
server allowlist as a markdown table, loom refuses to run when the
canonical config names a server or endpoint that is not in it. Policy and
generated config can then never disagree.

---

## Install

Requirements: `bash` 4+, `jq`, `git`. macOS and Linux.

```
git clone <this repo> ~/dev/loom
~/dev/loom/install.sh /path/to/your/repo
```

That copies `loom.sh`, `lib/`, a pre-filled `loom.config.json`, the Claude
Code skill, and starter spec packs into your repo:

| What | Default location | Change with |
|---|---|---|
| tool + config | `agent/tools/loom.sh`, `agent/tools/lib/`, `agent/tools/loom.config.json` | `--tools-dir` |
| Claude Code skill | `.claude/skills/loom/SKILL.md` | `--skills-dir` |
| spec packs | `agent/harness-specs/*.md` | `--specs-dir` |

Re-running the installer refreshes the tool and skill and leaves your
config and spec packs alone. `--link` symlinks the tool to your clone of
this repo instead of copying, for when you are developing loom itself.

Claude Code users can also load the skill as a plugin: this repo carries a
`.claude-plugin/plugin.json`, so `claude plugin install` from a marketplace
that lists it, or a local path, gives you `/loom` without the installer.
You still need the tool in the repo for the generation step.

## Use

1. **Configure.** Open `agent/tools/loom.config.json`. The paths default
   to the Claude Code layout; you usually only set three things:

   ```json
   {
     "paths": { "mcp_allowlist": "agent/policies/allowed-mcp-servers.md" },
     "mcp_note": "All listed servers are read-only documentation services.",
     "mcp_overrides": {
       "devin": {
         "context7": { "command": "npx", "args": ["-y", "mcp-remote@0.8.3", "{{url}}"] }
       }
     }
   }
   ```

   `mcp_allowlist` turns on the policy gate. `mcp_note` is free text
   written into adapters that allow comments. `mcp_overrides.devin`
   routes named servers through a stdio bridge, which Devin needs for
   servers that reject its discovery GET. Every key is documented in
   [`loom.config.example.json`](loom.config.example.json).

2. **Generate.**

   ```
   agent/tools/loom.sh            # write the adapters and GAPS.md
   agent/tools/loom.sh --check    # exit 1 with a diff if anything drifted
   agent/tools/loom.sh devin      # only one harness (GAPS.md is left alone)
   agent/tools/loom.sh --list     # emitters found in lib/
   ```

3. **Gate it.** Add the check to whatever runs on every change:

   ```make
   lint:
   	@bash agent/tools/loom.sh --check
   ```

4. **Commit** the generated files together with the config that produced
   them. Never edit a generated file; change the source or the emitter and
   rerun loom. The generated files say so in their header (opencode's
   schema rejects unknown keys, so there the `--check` gate is the marker).

5. **When a harness changes its format**, run the `loom` skill in Claude
   Code. It walks through refreshing the dated spec pack from current
   docs, changing the emitter if the schema moved, regenerating, and
   verifying. That is the only part of loom that needs judgment, and it
   is kept separate from generation on purpose.

## How it works

`loom.sh` does four things in order.

**Gate.** If `paths.mcp_allowlist` is set, every `mcpServers` entry in
`.mcp.json` must appear in the file's `## Approved servers` table with the
same endpoint. A name reused for a different URL is refused.

**Normalise.** The canonical files are folded into one intermediate
representation (IR), a JSON document every emitter reads:

```json
{
  "mcp":         [{ "name": "context7", "type": "http", "url": "...", "overrides": { "devin": {...} } }],
  "permissions": { "allow": ["Bash(make lint)", "mcp__context7__*"] },
  "hooks":       { "PreToolUse": [...], "PostToolUse": [...] },
  "context":     "AGENTS.md",
  "meta":        { "loom_script": "...", "config_path": "...", "mcp_note": "...",
                   "hook_gap_control": { "default": "..." }, "permission_gap_control": { "default": "..." } }
}
```

**Emit.** Each `lib/emit-<harness>.sh` defines `emit_<harness> IR OUT`
and writes its files under `OUT`. When it meets something it cannot
express it calls `gap_add <harness> "<what>" "<compensating control>"`.
The control text comes from `compensating_controls` in the config, per
harness or as a default.

**Apply or check.** In apply mode the files are copied into the repo. In
check mode they are diffed against the committed copies; any difference,
or a generated file that was never committed, fails the run.

Spec packs are not read at runtime. They are the dated, sourced evidence
for what each emitter hardcodes, and loom warns when one is older than
`spec_pack_max_age_days`.

### What each emitter produces

| Harness | Files | Carries | Cannot carry (goes to GAPS.md) |
|---|---|---|---|
| Codex | `.codex/config.toml` | MCP servers with tool calls pre-approved; header comment with your note | hooks; per-tool permission globs |
| Devin | `.devin/mcp_config.json`, `.devin/config.json`, `.devin/hooks.v1.json` | MCP servers (native HTTP or stdio bridge), `mcp__*` permissions, every hook event Devin supports with `$CLAUDE_PROJECT_DIR` rewritten | non-MCP permission entries such as `Bash(...)` |
| opencode | `opencode.json` | MCP servers as remote entries | hooks; any permission entries |

### Writing an emitter

Create `lib/emit-<name>.sh`:

```bash
#!/usr/bin/env bash
# <name> emitter. Spec pack: harness-specs/<name>.md
emit_<name>() {
  local ir="$1" out="$2"
  mkdir -p "${out}/.<name>"
  jq -r '.mcp[] | ...' "${ir}" > "${out}/.<name>/config"
  # anything you drop:
  while IFS= read -r event; do
    [[ -n "${event}" ]] && gap_add <name> "hook event: ${event}" \
      "$(jq -r '.meta.hook_gap_control | .<name> // .default' "${ir}")"
  done < <(jq -r '.hooks | keys[]' "${ir}")
}
```

Write `harness-specs/<name>.md` with a `generated:` date, the file
schema, the source URLs, and what the harness does not support. Loom
discovers the emitter on the next run; no core change is needed.

## Repository layout

```
loom.sh                     the tool
lib/emit-*.sh               one emitter per harness
loom.config.example.json    every config key, documented
skills/loom/SKILL.md        the Claude Code skill (Phase A: refresh)
harness-specs/*.md          starter spec packs, seeded 2026-09-03
install.sh                  copies the above into a repo
tests/smoke.sh              end-to-end test in a throwaway repo
.claude-plugin/plugin.json  plugin manifest for the skill
```

Run `tests/smoke.sh` before sending a change. It installs loom into a
fixture repo and checks generation, the drift gate, the allowlist gate,
the hook translation, the gaps ledger, the staleness warning, and that
re-installing preserves config.

## Limits worth knowing

- Loom translates project-scoped config only. It cannot remove an MCP
  server a developer added at user scope in their own harness; that needs
  org-managed settings or network egress rules.
- The Devin hook translation assumes Devin's edit tools expose the same
  `tool_input.file_path` field as Claude Code. If they do not, a path-based
  hook is inert there rather than wrongly blocking.
- The allowlist gate parses a markdown table: server name in the first
  column, endpoint in the second, under a `## Approved servers` heading.

## License

Loom is licensed under the [GNU Affero General Public License v3.0](LICENSE).
You may use, study, modify, and redistribute it freely — but any derivative
work, including one offered as a network service, must also be released under
the AGPL-3.0 with its source. If your organization needs a non-AGPL commercial
license, open an issue to discuss it.

## Origin

Extracted from the `sre-stack` repository, where it keeps four harnesses
in lockstep under a spec-driven SDLC. The design notes it follows: one
source of truth, deterministic translation, a drift gate in lint, and
"silent loss is the failure mode" for anything a harness cannot express.
