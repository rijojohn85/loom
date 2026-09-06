# Quickstart: Running the Loom E2E Test System

Validation guide for the design in [plan.md](./plan.md). Paths are
repository-relative. Nothing here is implementation code — see `tasks.md` once
`/speckit-tasks` has run.

## Prerequisites

| Need | Check | If missing |
|---|---|---|
| bash 5+, git, jq, python3 3.11+ | `tests/e2e/run.sh --list` prints prerequisites | Install; the runner names the missing one and exits 5 |
| Schema validator | `tests/e2e/run.sh --bootstrap` | Creates `tests/e2e/.venv` with the pinned `jsonschema` (the only network step). Without it, schema checks report **blocked** |
| `claude` | `claude --version` (pinned 2.1.263) | Live and intent suites report **blocked** |
| `codex` | `codex --version` (pinned 0.153.4) | Codex conformance reports **blocked** |
| `opencode` | `opencode --version` (pinned 1.18.29) | opencode conformance reports **blocked** |
| Devin | — | Deferred: adapters validated offline, live claims recorded **unverified** |

Nothing needs to be approved by hand. The runner seeds project trust and MCP
approval into its own isolated config directory — see *Trust* under §4.

## 1. The offline gate (the one you run on every change)

```bash
tests/e2e/run.sh                 # defaults to --suite offline
```

Expected: exit 0 in under 3 minutes, no network, no model. The last lines read
(check counts grow with `--variant all`; capability counts are fixed by the
inventory in `oracle/capabilities.json`):

```text
verdict: offline-pass (offline layer only — not full end-to-end)
checks: 25 passed · 0 failed · 0 blocked · 0 skipped
capabilities: 9 preserved · 2 verified-compensated · 45 approved-gap · 0 failed · 7 unverified (devin)
results: tests/e2e/results/<run-id>/results.json
```

Note what this does **not** say: it never prints an unqualified "pass", and the
45 approved-gap entries and 7 unverified Devin entries stay outside the pass
count.

The first check in this suite is `offline.smoke`, which runs `tests/smoke.sh`
unmodified. That script also still works on its own:

```bash
tests/smoke.sh                   # unchanged; KEEP=1 to retain its fixture
```

## 2. Prove the suite can fail

```bash
tests/e2e/run.sh --suite mutation
```

Every entry in `tests/e2e/oracle/mutations.json` is applied to a throwaway copy,
and the named validator must fail with a reason matching the declared pattern.
Expected output shape:

```text
passed  mutation.weaken-deny        validator offline.capabilities.codex failed as declared
passed  mutation.drop-hook-order    validator offline.variant.hook-ordering failed as declared
failed  mutation.corrupt-schema-field  validator passed — planted defect not detected
```

The third line is what a broken test system looks like: the mutation suite fails
when a validator *doesn't* catch its defect, or catches it for the wrong reason.

## 3. Live skill execution (opt-in, costs money)

```bash
tests/e2e/run.sh --suite live --keep
```

Requires Claude Code credentials. There is no default time or spend ceiling —
that was a deliberate decision — so the run prints progress and running
consumption, and you can set one explicitly with `--timeout` / `--ceiling-usd`.

Expected evidence in `tests/e2e/results/<run-id>/evidence/live.skill-invocation/`:

- `stream-json.jsonl` containing the Skill invocation for `loom`
- a tool-use event referencing `agent/tools/loom.sh` and the generator's
  `loom: emitted N adapter set(s)` output
- `hook-audit.log` copied from the workspace — written by Claude Code running the
  fixture's own hooks, so it doubles as proof project config loaded
- `changed-files.json`, `consumption.json`, `oracle-digest-before/after.txt`

If the oracle digests differ, the run exits 4 and reports an oracle-integrity
failure. That is never fixed by editing expectations.

## 4. Harness conformance

```bash
tests/e2e/run.sh --suite conformance --harness codex --harness opencode
```

Each check records the exact interface used and the version observed:

```text
passed  conformance.codex.strict-config      codex 0.153.4  `codex --strict-config`
passed  conformance.codex.mcp-list           codex 0.153.4  `codex mcp list`
passed  conformance.codex.context-in-prompt  codex 0.153.4  `codex debug prompt-input`
passed  conformance.opencode.resolved-config opencode 1.18.29  `opencode debug config`
blocked conformance.devin.*                  no local Devin interface — unverified
```

Locally this runs `--advisory` when your auto-updated Codex or opencode drifts off
the pin: results are labelled `pinned: false` and cannot be cited as gate
evidence. In CI (`CI=true`) the default is `--pinned`, and a mismatch reports the
layer **blocked** with a pointer to the `loom` skill's Phase A refresh.

Each of these has a negative control: the same probe re-run with `--safe-mode`
(Claude), `--pure` (opencode), or the project config removed must **not** see the
canary. A canary visible in both runs fails the check.

### Trust: why a fresh temp workspace needs seeding

A newly created `/tmp` workspace is untrusted. The failure this causes is silent,
not loud — measured on the pinned versions:

| Harness | Untrusted temp workspace | After seeding |
|---|---|---|
| Codex | `codex mcp list --json` → `[]`, exit **0** — project config ignored, command "succeeds" | server listed with its transport |
| Claude Code | `claude mcp list` → `⏸ Pending approval`, exit **0** | server connects |
| opencode | project config already loaded — no gate | unchanged |

The runner therefore seeds, before any probe and only inside the run's own config
directory:

- `$CODEX_HOME/config.toml` → `[projects."<workspace>"]` with `trust_level = "trusted"`
- `$CLAUDE_CONFIG_DIR/.claude.json` → `projects["<workspace>"]` with
  `hasTrustDialogAccepted`, `enabledMcpjsonServers` for the fixture servers, and
  `hasClaudeMdExternalIncludesApproved` (the fixture's `CLAUDE.md` imports
  `AGENTS.md`, which is separately gated)

What was seeded is recorded in `workspace.json`. To verify the probes actually
detect an ignored project file, run the negative case:

```bash
tests/e2e/run.sh --suite conformance --no-trust-seed
```

Expected: the Codex and Claude checks report **failed/blocked with the untrusted
reason**, and opencode still loads. If a trust-gated harness appears to see
project config with seeding skipped, the probe is reading something else and the
suite says so.

## 5. Intent and behaviour

```bash
tests/e2e/run.sh --suite intent
```

Scenarios establish the Claude Code baseline first, then evaluate each target.
Deterministic probes run wherever the harness supports them; model-driven
scenarios use the trial count and threshold declared in the scenario file, and
every attempt is retained. A forbidden side effect fails immediately and no
later attempt clears it.

## 6. Full mode

```bash
tests/e2e/run.sh --full
```

Runs every suite against every **required** harness — Claude Code as the baseline,
Codex and opencode as targets. Devin is deferred, so its checks are recorded
`unverified` and are not mandatory: on their own they do **not** make full mode
nonzero, but they never count toward a pass either, and the verdict note says so.

Full mode exits 3 when a *mandatory* check is blocked or skipped — no Claude Code
credentials, a missing Codex or opencode binary, or a version mismatch under
`--pinned`. With credentials present and both target harnesses installed at their
pinned versions, `--full` exits 0 and prints `verdict: full-e2e-pass`, with the
Devin capabilities still visible in the unverified column.

## 7. Retention and cleanup

- Default `--keep-on-failure`: failed runs keep their workspace; the path is
  printed and recorded in `workspace.json`.
- `--keep` retains always; `--clean` removes the workspace even on failure.
- Cleanup only ever removes paths the run created. The committed fixture and the
  oracle are verified unchanged at the end of every run.
- Retained logs pass through redaction; a file matching a credential pattern is
  refused rather than written.

## 8. Concurrency

```bash
tests/e2e/run.sh --suite offline & tests/e2e/run.sh --suite offline & wait
```

Both must pass, with distinct workspaces, ports, and results directories.

No lock is needed for the shared `/tmp/opencode` temp path (research watch
item): every opencode invocation the suite makes is allocated a unique port
from the run's `ports.json` (`opencode run --port <n>`), so concurrent runs do
not share server state. The CI offline gate (`e2e-offline.yml`) runs two
simultaneous offline runs as the standing SC-011 check.

## 9. CI

Two jobs, never merged:

| Job | Command | Gates? |
|---|---|---|
| `e2e-offline` | `tests/e2e/run.sh --suite offline --suite mutation` | Yes — on every PR, pinned, no credentials |
| `e2e-live` | `tests/e2e/run.sh --full` | Opt-in, credentialed, nonzero when any required layer is blocked |
| `compat-latest` | conformance against latest harness versions | No — reports drift only, never gates |
