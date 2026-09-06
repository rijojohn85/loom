# Contract: `tests/e2e/run.sh`

The single documented entry point (FR-001). Exit status and printed verdict are
part of the contract; so is the refusal to overstate a result.

## Synopsis

```text
tests/e2e/run.sh [--suite S ...] [--full] [--harness H ...] [--variant V ...]
                 [--keep | --keep-on-failure | --clean]
                 [--timeout SECONDS] [--ceiling-usd N] [--trials N]
                 [--pinned | --advisory]
                 [--results-dir DIR] [--bootstrap] [--list] [--help]
```

## Options

| Option | Default | Meaning |
|---|---|---|
| `--suite S` | `offline` | Repeatable. One of `offline`, `mutation`, `live`, `conformance`, `intent`. |
| `--full` | off | Every suite, every required harness; mandatory checks must all pass. |
| `--harness H` | all available | Repeatable: `claude`, `codex`, `opencode`, `devin`. Devin is structural-only today. |
| `--variant V` | base | Repeatable fixture variant; `--variant all` runs every declared variant. |
| `--keep` / `--keep-on-failure` / `--clean` | `--keep-on-failure` | Workspace retention. Cleanup only ever removes paths this run created. |
| `--timeout SECONDS` | unset | Optional per-scenario wall-clock ceiling. Unset means unbounded (clarified decision). |
| `--ceiling-usd N` | unset | Optional model-spend ceiling per run. Unset means unbounded; consumption is reported either way. |
| `--trials N` | scenario default | Override model-driven trial count; thresholds still come from the scenario. |
| `--pinned` / `--advisory` | `--pinned` in CI (`CI=true`), `--advisory` locally | `--pinned` blocks a harness layer on version mismatch; `--advisory` runs it and labels every outcome unpinned. |
| `--no-trust-seed` | off | Skip trust seeding, for the untrusted-canary negative check. Any harness with a trust gate is then expected to *fail* to see project config; a run where it still does is a probe failure. |
| `--results-dir DIR` | `tests/e2e/results` | Where the run directory is created. |
| `--bootstrap` | — | Create the local virtualenv and install the pinned `jsonschema`, then exit. The only step that needs network. |
| `--list` | — | Print suites, variants, harnesses, and check ids, then exit. |

## Exit status

| Code | Meaning |
|---|---|
| 0 | Every selected mandatory check passed. With `--full`, this is a full end-to-end pass. |
| 1 | At least one check failed. |
| 2 | Usage error. |
| 3 | A mandatory check was blocked or skipped (missing harness, missing credentials, version mismatch under `--pinned`, absent schema validator). Never printed as a pass. A **deferred** target's `unverified` checks are not mandatory and do not by themselves produce this code — they simply never count toward a pass. |
| 4 | Oracle integrity failure: the oracle tree changed during a run. |
| 5 | Prerequisite check failed before any suite ran. |

`--full` returns nonzero whenever any **required** harness or mandatory layer is
blocked or skipped (FR-047, SC-007). Devin is deferred, not required, so its
absence alone does not make full mode nonzero; its capabilities stay in the
`unverified` column and outside every pass total (FR-043a).

## Output

- `stdout`: one line per check — `state  check-id  [harness]  reason`, then a
  verdict block naming the mode, the counts per state, and the results path.
- `<results-dir>/<run-id>/results.json` — conforms to `results.schema.json`.
- `<results-dir>/<run-id>/report.md` — the human report (FR-056).
- `<results-dir>/<run-id>/evidence/…`, `workspace.json`, `resolved-input.json`.

The verdict line names the mode explicitly. An offline-only run prints
`verdict: offline-pass (offline layer only — not full end-to-end)` and never the
word "pass" unqualified (FR-004).

## Environment

| Variable | Purpose |
|---|---|
| `LOOM_E2E_KEEP` | Same as `--keep`, for CI. |
| `ANTHROPIC_API_KEY` / configured Claude Code credentials | Live and intent suites; absent means those layers are **blocked**. |
| `CI` | Selects `--pinned` default. |

Every other environment variable is scrubbed for harness child processes;
`HOME`, `XDG_*_HOME`, `CODEX_HOME` and `CLAUDE_CONFIG_DIR` are set to per-run
paths under `<results-dir>/<run-id>/home/` (FR-021). Project trust and MCP
approval are seeded into those per-run files only, and never into the developer's
real configuration; the runner refuses to seed a path outside the run directory.

## Prerequisites

Checked before any suite runs, reported individually, and fatal (exit 5) only when
a *selected* suite needs them: `bash` 5+, `git`, `jq`, `python3` 3.11+, the
bootstrapped `jsonschema` venv, the selected harness CLIs, and credentials for
live layers.
