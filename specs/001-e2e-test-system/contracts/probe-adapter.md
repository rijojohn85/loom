# Contract: harness probe adapter

Every target harness is reached through one adapter at `tests/e2e/probes/<harness>.sh`.
Adding a harness means adding one adapter and one pins entry — nothing in the
runner, the oracle format, or the report changes (Principle X).

An adapter defines these functions. Each prints one JSON object to stdout and
returns 0 on success, 3 when the capability cannot be exercised (blocked), and 1
on a genuine failure. Every payload includes `harness_version_observed` and
`interface` (the exact command used), because a claim without its interface is not
evidence.

| Function | Must answer | Verified interface today |
|---|---|---|
| `probe_available` | Is the harness installed and runnable? | `--version` |
| `probe_version` | Which version is present? | `--version` |
| `probe_isolated` | Does it read user state from the per-run paths only? | opencode: `debug paths`; Codex: `$CODEX_HOME` + `doctor --json`; Claude: `CLAUDE_CONFIG_DIR` self-check (verified) |
| `seed_trust` | Mark the workspace trusted and approve its project MCP servers, in the per-run config only | Codex: `[projects."<ws>"] trust_level = "trusted"` in `$CODEX_HOME/config.toml`; Claude: `projects["<ws>"].hasTrustDialogAccepted` + `enabledMcpjsonServers` + `hasClaudeMdExternalIncludesApproved` in `$CLAUDE_CONFIG_DIR/.claude.json`; opencode: no gate — returns `not-applicable`, recorded as an observed fact |
| `probe_trust_state` | Is the workspace trusted right now, and what did seeding change? | Re-run `probe_mcp_list` / `probe_loaded_config` before and after seeding |
| `probe_loaded_config` | What configuration did it actually load? | Codex `doctor --json`; opencode `debug config` |
| `probe_unknown_field` | Does it reject a field it does not support? | Codex `--strict-config`; opencode schema validation of `opencode.json` |
| `probe_mcp_list` | Which MCP servers did it resolve? | Codex `mcp list` / `mcp get`; opencode `mcp list` |
| `probe_mcp_call` | Does a permitted call to the fixture service succeed? | Codex `exec --json`; opencode `run --format json` |
| `probe_context_loaded` | Did the canonical context reach the model prompt? | Codex `debug prompt-input`; Claude `-p --output-format stream-json` |
| `probe_permission` | Is a forbidden action refused with no side effect? | Claude `--permission-prompts none`; Codex `--sandbox read-only`; opencode without `--auto` |
| `probe_hook_audit` | Which hooks ran, in what order? | The fixture's audit log in the workspace |
| `probe_native_assets` | Does the harness see skills/agents natively? | opencode `debug skill`, `agent list`; used to fill `native_equivalent` on gaps |

Adapters that cannot implement a function return **blocked** with a reason naming
the missing interface. They must never emulate a harness by re-parsing the
generated file, and must never invent a flag: the Devin adapter implements only
`probe_available` (blocked) and reports every other function as `unverified`.

Every adapter must return, from `seed_trust`, the exact file it wrote and the
servers it approved; the runner copies this into `workspace.json`. An adapter must
never write trust into the developer's real configuration — the runner asserts the
written path is inside the run's private state directory before calling it.

## Negative control

`probe_loaded_config` and `probe_context_loaded` must be run twice: once normally,
and once with the harness's customisation disabled (`claude --safe-mode`, opencode
`--pure`, Codex with the project config removed from the workspace copy). The
canary must appear in the first run and be absent in the second. A canary that
appears in both proves the probe is reading something other than project
configuration, and the check fails.

A second, sharper negative control covers trust: run `probe_mcp_list` **before**
`seed_trust`. Observed reference behaviour on the pinned versions — Codex returns
`[]` with exit 0, Claude Code reports `⏸ Pending approval` with exit 0, opencode
loads the config with no gate. The untrusted result must differ from the seeded
one for any harness that has a gate; if it does not, the probe is not reading
project configuration and the check fails regardless of what the seeded run
showed. This is the concrete demonstration that a zero exit status is not
evidence.
