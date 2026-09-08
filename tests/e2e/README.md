# Loom end-to-end test system

Five selectable suites behind one entry point. The fast offline gate runs on
every change; live skill execution, harness conformance and behavioural
intent probes run opt-in. See `specs/001-e2e-test-system/quickstart.md` for
the run guide.

```bash
tests/e2e/run.sh                                  # offline gate (default suite)
tests/e2e/run.sh --suite offline --variant all    # offline over every fixture variant
tests/e2e/run.sh --suite mutation                 # prove the validators fail on demand
tests/e2e/run.sh --suite live --keep              # real skill run (costs money)
tests/e2e/run.sh --suite conformance --harness codex --harness opencode
tests/e2e/run.sh --suite intent                   # behavioural scenarios
tests/e2e/run.sh --full                           # everything, every required harness
tests/e2e/run.sh --bootstrap                      # install the pinned jsonschema venv (only network step)
tests/e2e/run.sh --list                           # suites, variants, harnesses, check ids
```

## Suites

| Suite | What it proves | Needs |
|---|---|---|
| `offline` | Deterministic, evidence-backed verdict over a fresh isolated workspace: smoke, artifact inventory, official-schema validation, idempotence, portability, drift, negative variants, capability classification, claim-kind audit. No network, no model. | bash 5+, git, jq, python3 3.11+, bootstrapped venv, harness CLIs for loader evidence |
| `mutation` | Every offline validator fails on a planted defect for the declared reason. A green offline run means something because this suite goes red on demand. | Same as offline |
| `live` | The installed skill is discovered and invoked through real Claude Code (three-signal proof: Skill event, generator invocation + marker, fixture hook audit log), plus no-change and stale-pack scenarios. | Claude Code credentials (opt-in, costs money) |
| `conformance` | Codex and opencode demonstrably load the generated adapters (loader probes, strict/schema rejection, MCP calls against fixture services, trust canaries, customisation negative controls). Devin stays unverified. | Harness CLIs; model auth only for MCP-call probes |
| `intent` | Observable behaviour per scenario after the Claude baseline: permitted calls, forbidden/protected/approval enforcement, hook order, context influence. Forbidden side effects fail permanently. | Credentials per harness; codex/opencode model auth where available |

## Flags

```
--suite S        offline | mutation | live | conformance | intent (repeatable; default: offline)
--full           every suite, every required harness; mandatory checks must all pass
--harness H      claude | codex | opencode | devin (repeatable; default: all)
--variant V      base fixture variant (repeatable; default: base); --variant all runs every declared variant
--keep | --keep-on-failure | --clean
                 workspace retention (default: --keep-on-failure; $LOOM_E2E_KEEP also honoured).
                 Cleanup only ever removes paths the run created (/tmp/loom-e2e-*).
--timeout SECONDS     optional per-scenario wall-clock ceiling (unset = unbounded by design)
--ceiling-usd N       optional model-spend ceiling per run (unset = unbounded; consumption reported either way)
--trials N            override model-driven trial counts (thresholds still come from the scenario files)
--pinned | --advisory pinned blocks a harness layer on version mismatch (CI default);
                 advisory runs and labels every outcome unpinned (local default)
--no-trust-seed  skip trust seeding (untrusted-canary negative check)
--results-dir DIR     where the run directory is created (default: tests/e2e/results)
--bootstrap      create the local virtualenv with the pinned jsonschema, then exit
--list           print suites, variants, harnesses, check ids and prerequisites, then exit
--help           print usage and exit
```

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Every selected mandatory check passed (with `--full`, a full end-to-end pass) |
| 1 | At least one check failed |
| 2 | Usage error |
| 3 | A mandatory check was blocked or skipped (missing harness, credentials, version mismatch under `--pinned`, absent validator). A deferred target's `unverified` checks never produce this code alone |
| 4 | Oracle integrity failure: the oracle tree changed during a run |
| 5 | Prerequisite failure before any suite ran |

An offline-only run prints `verdict: offline-pass (offline layer only — not
full end-to-end)` and never an unqualified pass. A full run prints
`verdict: full-e2e-pass` only when every mandatory check passed.

## Result states

Checks: `passed` · `failed` · `approved-gap` · `skipped` · `blocked`.
Capabilities: `preserved` · `verified-compensated` · `approved-gap` ·
`failed` · `unverified`. Approved gaps and unverified entries are never
folded into a pass count.

## Layout

```
tests/e2e/
  run.sh            entry point (this guide's commands)
  lib/              workspace, isolate, trust, install, ports, evidence,
                    result, report, oracle, prereq, assert
  suites/{offline,mutation,live,conformance,intent}/
  probes/           one adapter per harness (contract in
                    specs/001-e2e-test-system/contracts/probe-adapter.md)
  fixtures/         complete-claude base + variants + local MCP services
  oracle/           capabilities, expected artifacts, approved gaps,
                    per-harness expectations, scenarios, mutations, rubric
  schemas/          vendored official schemas + provenance
  pins/             harness, dependency and schema pins with digests
  tools/            parse, schema_validate, digest, compare, redact
  results/          per-run evidence (git-ignored)
```

## Installation

No installation. Requirements are checked per run (`--list` prints them);
base tooling is fatal (exit 5), suite-scoped needs become honest `blocked`
checks. The only network step is `--bootstrap`.

## Reproducible execution

Pins (`pins/harnesses.json`, `pins/dependencies.json`, `pins/schemas.json`)
record harness, tool, dependency and schema versions plus digests. Every run
embeds its pins in `results.json`. Gating runs require exact harness matches;
local runs proceed `--advisory` with outcomes labelled unpinned. Live
upstream compatibility (latest harness versions) belongs in a separate,
clearly labelled job and never gates reproducible runs.

## Refreshing upstream pins

1. Install the new harness version; run the conformance suite.
2. On drift, run the `loom` skill's Phase A refresh workflow (spec packs
   carry `harness_version:` for exactly this).
3. Update `pins/harnesses.json` (version + interfaces + date) and any
   vendored schema (`pins/schemas.json` with new digest) in the same change
   as the specification evidence that justifies it — never to make a failing
   expectation pass.
4. Re-run offline + mutation pinned.

## Extending the fixture and capability inventory

1. Add the construct to `fixtures/complete-claude/` (and a variant under
   `fixtures/variants/<name>/` with a `manifest.json` declaring the change
   and the expected generation outcome).
2. Add one `CapabilityRecord` per new behaviour to
   `oracle/capabilities.json` (hand-authored; never derived from output),
   with per-harness expectations and required evidence.
3. Add reviewed `ApprovedGap` entries for losses (`oracle/approved-gaps.json`,
   exact gap ids — pattern rules are forbidden).
4. Add a mutation case that breaks the new validator for its declared reason.
5. Oracle changes are a separate, separately justified change,
   never authored by the process they validate (see CODEOWNERS).

## Adding a further target harness to the required set

1. Add one probe adapter `probes/<harness>.sh` implementing the contract in
   `specs/001-e2e-test-system/contracts/probe-adapter.md` (verified flags
   only — never invent an interface; return `blocked`/`unverified` honestly).
2. Add its pin entry (`pins/harnesses.json`) and spec pack
   (`agent/harness-specs/<harness>.md` with `harness_version:`).
3. Add per-harness expectations under `oracle/expectations/<harness>/` and
   dispositions for every capability (or `unverified` while deferred).
4. Nothing in the runner, oracle format or report changes.

## Gap review process

Gaps live in `oracle/approved-gaps.json`: exact gap id, capability,
harness, disposition with reviewer, review date, `native_equivalent`, and a
`compensating_control` naming the check that demonstrates it (or null, in
which case the state stays `approved-gap`, never `verified-compensated`).
Review cadence: every release or added harness, whichever comes first. A gap
whose native equivalent appears (see `intent.assets-gaps`) is re-reviewed,
not silently closed.

## Oracle-change review convention

Any change to expectations, schemas, approved gaps or the intent manifest is
a separate, separately justified change: what behaviour changed, why the old
expectation was wrong, and what evidence supports the new one. "The
implementation does not do this" is never sufficient justification.
`tests/e2e/oracle/` is CODEOWNERS-protected, digest-verified before and after
every live phase, and read-only for its duration.
