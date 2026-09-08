# Phase 0 Research: End-to-End Test System for Loom

**Date**: 2026-09-06 · **Method**: direct probing of the harness CLIs installed on
the development machine, plus reading of `loom.sh`, `install.sh`, `lib/emit-*.sh`,
`skills/loom/SKILL.md` and the committed spec packs. Every interface listed as
verified below was observed on this machine on this date; anything not observed is
labelled assumed or unverified.

## Versions observed (candidate pin set)

| Component | Version observed | How |
|---|---|---|
| Claude Code | 2.1.263 | `claude --version` |
| Codex CLI | 0.153.4 | `codex --version` |
| opencode | 1.18.29 | `opencode --version` |
| jq | 1.7.1 | `jq --version` |
| Python | 3.14.7 | `python3 --version` |
| Devin | not installed | no local CLI exists; hosted service |
| Docker | not installed | container-based arrangements are unavailable |

## D1. Conformance interfaces per harness

**Decision**: Use each harness's own inspection commands as the loader evidence;
do not invent flags and do not treat a format parser as a loader.

**Verified — Codex 0.153.4**

| Interface | What it gives us | Requirement served |
|---|---|---|
| `codex --strict-config` / `codex exec --strict-config` | "Error out when config.toml contains fields that are not recognized by this version of Codex" — real unknown-field rejection at the loader | FR-036, FR-045 |
| `codex doctor --json` | "Emit a redacted machine-readable report" of installation, config, auth and runtime health | FR-045 |
| `codex mcp list` / `codex mcp get <name>` | The MCP servers Codex actually resolved | FR-046 |
| `codex debug prompt-input` | "Render the model-visible prompt input list as JSON" — proves whether the context file reached the prompt, with no model spend | FR-048, FR-049 |
| `codex exec --json -C <dir> --sandbox read-only --output-last-message <file>` | JSONL event stream for behavioural scenarios, confined to a directory and a read-only sandbox | FR-048, FR-050 |
| `$CODEX_HOME` | Referenced by `codex --help` for layered user config; the isolation lever for user-level state | FR-021, FR-022 |

**Verified — opencode 1.18.29**

| Interface | What it gives us | Requirement served |
|---|---|---|
| `opencode debug config` | "show resolved configuration" — the effective loaded config, not a re-parse of our own file | FR-045 |
| `opencode debug paths` | "show global paths (data, config, cache, state)" — proves where user state is being read from | FR-022 |
| `opencode mcp list` | "list MCP servers and their status" | FR-046 |
| `opencode debug skill`, `opencode agent list`, `opencode debug agent <name>` | Native skill/agent visibility — the probe that will later confirm feature `002-link-context-assets`, and today the evidence that a native equivalent exists for a recorded gap | FR-012a |
| `opencode run --format json --dir <dir> --port <n> --pure` | Raw JSON events, explicit working directory, explicit port, and plugin-free execution | FR-024, FR-048 |
| `HOME` + `XDG_CONFIG_HOME` / `XDG_DATA_HOME` / `XDG_CACHE_HOME` | Isolation, **verified by probe**: with those set, `opencode debug paths` reported config, data, cache and log under the temporary tree | FR-021 |

**Verified — Claude Code 2.1.263 (source baseline and skill host)**

| Interface | What it gives us | Requirement served |
|---|---|---|
| `claude -p --output-format stream-json --include-partial-messages` | Structured event stream: tool uses, skill invocation, file writes | FR-027, FR-028 |
| `--settings <file-or-json>`, `--setting-sources user,project,local` | Explicit control over which settings sources load — the lever for proving project configuration was used | FR-022 |
| `--mcp-config`, `--strict-mcp-config` | Explicit MCP sources; `--strict-mcp-config` ignores every other MCP configuration | FR-046 |
| `--permission-mode`, `--permission-prompts none` | Deterministic permission behaviour: with `none`, anything that would prompt is denied automatically — the approval-required probe | FR-048 |
| `--safe-mode` | Disables all customizations (CLAUDE.md, skills, hooks, MCP, agents) — the negative control for every "did project config load?" canary | FR-045 |
| `--add-dir`, `--session-id`, `--debug-file`, `--model` | Directory confinement, reproducible session identity, debug capture, model pinning | FR-021, FR-028 |
| `$CLAUDE_CONFIG_DIR` | User-config isolation. **Assumed** (documented Claude Code env var, not probed here); falsified if a run with it set still reads the developer's user settings — the isolation self-check in FR-022 tests exactly that | FR-021 |

**Devin**: no local CLI and no container runtime on this machine. Per the
clarification, Devin adapters are validated structurally offline and every Devin
conformance/behaviour claim is recorded `unverified`. No invented interface.

**Alternatives rejected**: driving each harness only through a model prompt
(slow, nondeterministic, and it cannot distinguish a config-loading failure from a
model failure); asserting on our own re-parse of the generated file (explicitly
forbidden by Principle III).

## D2. Schema validation strategy

**Decision**: Three named claim kinds, recorded per check and never conflated:

1. `official-schema` — opencode publishes `https://opencode.ai/config.json`
   (already referenced by `lib/emit-opencode.sh`). Vendor it under
   `tests/e2e/schemas/` with source URL, retrieval date, version and SHA-256, and
   validate with a pinned `jsonschema`.
2. `harness-loader-probe` — Codex has no published config schema, but
   `--strict-config` rejects unknown fields at the loader, which is stronger
   evidence than a schema check. Codex conformance therefore requires the probe.
3. `local-structural` — Devin's JSON files and anything else without an official
   schema. Labelled as a local structural check in the report; never reported as
   schema validation.

**Bootstrap**: `run.sh --bootstrap` creates `tests/e2e/.venv` and installs the
pinned `jsonschema`. If the venv is absent, schema checks report **blocked**, not
skipped and never passed. Parsing itself needs no dependency: Python stdlib
`json` and `tomllib` (3.11+) parse both formats properly.

**Alternatives rejected**: `ajv`/`check-jsonschema` (not installed, adds a Node or
pipx dependency); a hand-written validator (could not honestly be called schema
validation); jq structural checks alone (fine as `local-structural`, insufficient
where an official schema exists).

## D3. Fixture MCP services and dynamic endpoints

**Decision**: Two Python stdlib services under `tests/e2e/fixtures/services/` — an
HTTP MCP service (streamable HTTP: `initialize`, `tools/list`, `tools/call`) and a
stdio MCP service — each with a fixed, tiny tool surface (`docs.get`, `docs.list`)
returning constant content and appending one line per call to an audit log.

Ports are allocated by binding port 0, then recorded in the run's
`resolved-input.json`. Both the fixture `.mcp.json` and the allowlist markdown are
templated with the allocated URL when the workspace is materialised, so the
allowlist gate sees a matching endpoint. Repeat-generation comparisons use the
same frozen resolved input, so bytes must match exactly. The cross-workspace
portability comparison normalises exactly one designated ephemeral field — the
allocated port — and records that it did.

**Alternatives rejected**: fixed well-known ports (collide across concurrent
runs); public MCP endpoints (forbidden by the brief); mocking the MCP protocol
inside the validator (would not exercise the harness's real MCP client).

## D4. Proving the installed skill actually ran

**Decision**: Require three independent signals, all of which must be present:

1. A `stream-json` event showing the Skill tool invoked with the `loom` skill from
   `.claude/skills/loom/SKILL.md` in the workspace.
2. A tool-use event whose input references the installed generator path
   (`agent/tools/loom.sh`), plus the generator's own stdout marker
   (`loom: emitted N adapter set(s)…`) in the captured output.
3. The fixture's own `PostToolUse` hook audit log in the workspace recording the
   Bash invocation — an artefact written by the harness, not by the test driver.

Additionally the workspace file digest map is captured before and after, giving
the changed-file set required by FR-028.

**Rationale**: any one signal alone can be faked by a well-meaning refactor of the
test driver; the hook audit log in particular is produced only if Claude Code
loaded the project's hook configuration, so it doubles as a config-loading canary.

**Alternatives rejected**: asserting only on exit status and changed files (cannot
distinguish the skill from a direct `loom.sh` call — explicitly forbidden by
FR-027); parsing the human-readable transcript (unstable).

## D5. Enforcing an unwritable oracle

**Decision**: Layered, with detection as the backstop:

1. **Physical separation** — the oracle lives at `tests/e2e/oracle/` in the source
   checkout and is never copied into the workspace; the workspace is an
   independent git repo under `/tmp`, and Claude Code is invoked with `--add-dir`
   limited to the workspace.
2. **Read-only during live phases** — the oracle tree is `chmod -R a-w` for the
   duration of any live or skill-driven phase.
3. **Digest verification** — a SHA-256 manifest of the oracle tree is taken before
   and after every live phase; any difference fails the run outright and is
   reported as an oracle-integrity failure, never as a test failure to be fixed by
   editing expectations.

No container runtime is available, so a read-only bind mount is not an option
today; if one appears, it slots in as a fourth layer without changing the design.

**Alternatives rejected**: instructing the model not to touch the oracle
(Principle IV forbids instruction-only isolation); keeping the oracle in a
separate repository (heavier to review, and the digest check already detects
tampering).

## D6. Workspace, isolation and concurrency

**Decision**: `/tmp/loom-e2e-<timestamp>-<pid>-<n>` with collision-safe suffixing,
created with `cp -a` semantics so dotfiles and executable bits survive; `git init`
inside; no symlink back to the checkout. Per-run environment: `HOME`,
`XDG_*_HOME`, `CODEX_HOME`, `CLAUDE_CONFIG_DIR` all pointed inside the run's
private state directory; only explicitly named credential variables are passed
through.

**Known caveat to handle**: `opencode debug paths` reports `tmp /tmp/opencode`, a
fixed shared path that does **not** move with `HOME`/`XDG_*`. Concurrent runs must
therefore treat opencode's temp directory as shared state — either serialise the
opencode conformance step behind a lock, or verify empirically that concurrent use
is safe. This is an implementation task, and the concurrency check (SC-011) is the
test that keeps it honest.

## D11. Trust and approval gating (verified by probe, 2026-09-06)

**Problem**: a fresh `/tmp` workspace is untrusted. The danger is not a prompt —
it is a harness that starts anyway, ignores the project configuration, and exits
0. That was demonstrated, not assumed:

| Harness | Fresh temp workspace, isolated user config | After seeding trust/approval |
|---|---|---|
| Codex 0.153.4 | `codex mcp list --json` → `[]`, **exit 0**. The project's `.codex/config.toml` server was silently ignored | Same command lists `probe-docs` with its resolved transport |
| Claude Code 2.1.263 | `claude mcp list` → `probe-docs … ⏸ Pending approval (run \`claude\` to approve)`, **exit 0** | Server moves to a real connection attempt |
| opencode 1.18.29 | `opencode debug config` already returned the project's `mcp.probe-docs` entry | No gate to seed |

**Decision**: seed trust into the per-run isolated user config before any probe,
never into the developer's real config, and record that it was seeded.

- **Codex** — write `$CODEX_HOME/config.toml` containing
  `[projects."<workspace>"]` / `trust_level = "trusted"` (the same shape the
  developer's own `~/.codex/config.toml` uses for this repository). Per-invocation
  equivalent: `-c 'projects."<workspace>".trust_level="trusted"'`.
- **Claude Code** — write `$CLAUDE_CONFIG_DIR/.claude.json` with
  `projects["<workspace>"] = { hasTrustDialogAccepted: true,
  enabledMcpjsonServers: [<fixture servers>],
  hasClaudeMdExternalIncludesApproved: true }`. The last key matters because the
  fixture's `CLAUDE.md` imports `AGENTS.md`; without it the import is gated.
  `CLAUDE_CONFIG_DIR` isolation is now **verified**, not assumed — the probe
  created `.claude.json` inside the temporary directory.
- **opencode** — nothing to seed; the absence of a gate is itself recorded as an
  observed fact, since a future version could add one.

**Consequence for validation**: trust seeding is a deliberate, recorded deviation
from a default-untrusted state, so the suite must also run the *unseeded* case as
a negative check (`conformance.<harness>.untrusted-canary`). Codex returning `[]`
with exit 0 is the reference example of why a zero exit status is not evidence,
and it is exactly what the canary probes must catch. A run whose canary passes in
the untrusted case has a broken probe.

**Also observed**: with `CODEX_HOME` under `/tmp`, Codex warns that it refuses to
create helper binaries under a temporary directory. Harmless, but the per-run
harness home directories therefore live under `<results-dir>/<run-id>/home/`
(repo-local, git-ignored) while the *workspace* stays in `/tmp` as the brief
requires.

## D7. Mutation harness

**Decision**: A declarative registry (`oracle/mutations.json`). Each case names an
id, the target (artifact path or behavioural scenario), the operation (weaken a
deny, drop a hook, change an MCP endpoint, omit an artifact, corrupt a schema
field, hand-edit a generated file, delete a generated file, orphan a file), the
validator id that must fail, and a regex the failure reason must match. The suite
applies each mutation to a throwaway copy, runs only the owning validator, and
asserts failure *and* reason. A mutation that fails the wrong validator, or fails
for the wrong reason, is itself a failure of the test system.

## D8. Reporting and state accounting

**Decision**: One `results.json` per run (schema in `contracts/results.schema.json`)
plus a rendered `report.md`. States are computed, never hand-written: the runner
refuses to emit a `passed` overall verdict when any mandatory check is `blocked`
or `skipped`, and refuses to emit a full-E2E verdict when only the offline layer
ran. Capability totals list `preserved`, `verified-compensated`, `approved-gap`,
`failed` and `unverified` separately; `approved-gap` and `unverified` are never
added into a pass count. Every evidence path is relative to the run directory, and
a redaction pass runs over retained logs before they are written.

## D9. Relationship to `tests/smoke.sh`

**Decision** (from clarification): `tests/e2e/run.sh --suite offline` invokes
`tests/smoke.sh` unmodified as its first check and records its result as a single
named check in `results.json`. Smoke keeps its own throwaway fixture and stays
independently runnable. New offline checks live beside it under
`tests/e2e/suites/offline/` and use the larger committed fixture.

## D10. Harness version pinning

**Decision**: Add a `harness_version:` field to each spec pack's front matter
(today they carry only `harness`, `generated:` and `status:`), record the same
values in `tests/e2e/pins/harnesses.json`, and have every conformance probe report
the version it observed. Gating runs require an exact match and report the layer
**blocked** on mismatch; local runs proceed and label every outcome
`unpinned/advisory`, which the result schema forbids counting as verified. A
mismatch message points at the `loom` skill's Phase A refresh workflow rather than
at the expectations.

## Open items carried into implementation

- Which credentials are available for automated live runs in CI (spec Assumptions).
- Whether opencode's shared `/tmp/opencode` requires a lock or is concurrency-safe.
- `CLAUDE_CONFIG_DIR` isolation was verified by probe on 2026-09-06; the
  self-check stays in place so a future version cannot regress it silently.
- Whether Codex or opencode change their trust behaviour between pinned versions —
  the untrusted-canary check detects it.

## D12. strict-config scope (amendment from implementation, 2026-09-06)

D1 described `codex exec --strict-config` as unknown-field rejection at the
loader. Probing on 0.153.4 falsified the project-config half: an unknown
top-level field and an unknown field inside `[mcp_servers."docs-a"]` in the
project `.codex/config.toml` did **not** stop exec (exit 0, model answered).
An unknown field in the user config (`$CODEX_HOME/config.toml`) **is**
rejected at startup (`config.toml:3:1: unknown configuration field`), before
any model or auth step. The conformance unknown-field check therefore targets
the isolated per-run user config, and the oracle expectation records the
project-level non-rejection explicitly rather than claiming adapter-level
rejection.
