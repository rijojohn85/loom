# Implementation Plan: End-to-End Test System for Loom

**Branch**: `001-e2e-test-system` | **Date**: 2026-09-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-e2e-test-system/spec.md`

## Summary

Build a layered test system that copies a committed Claude Code fixture into an
isolated temporary repository, installs Loom from the working checkout, drives the
installed skill through real Claude Code, and judges every artifact and behaviour
against an independently authored oracle that the tested process cannot write.

The approach is bash-first (matching Loom itself) with Python 3 stdlib validators
for real JSON/TOML parsing and digesting, one entry point (`tests/e2e/run.sh`)
owning five selectable suites, and conformance driven by interfaces that were
verified to exist on the installed harnesses during Phase 0 — notably
`codex --strict-config`, `codex doctor --json`, `codex mcp list`,
`codex debug prompt-input`, `opencode debug config`, `opencode mcp list`, and
`claude -p --output-format stream-json`. Because a fresh temporary workspace is
untrusted — and an untrusted Codex silently returns an empty server list with exit
0 — the runner seeds project trust into the per-run isolated user config and keeps
an unseeded negative check to prove the probes notice when it is missing. Existing `tests/smoke.sh` is called
unchanged as part of the offline layer.

## Technical Context

**Language/Version**: Bash 5 (test drivers, matching `loom.sh` and `tests/smoke.sh`); Python 3.11+ for validators (3.14.7 present locally — `tomllib`, `json`, `hashlib` from stdlib)

**Primary Dependencies**: `jq` 1.7.1, `git`, `python3` stdlib; `jsonschema` (pinned, installed into a project-local virtualenv by an explicit bootstrap step — its absence blocks schema checks, never passes them); harness CLIs `claude` 2.1.263, `codex` 0.153.4, `opencode` 1.18.29

**Storage**: Files only. Committed fixtures, a read-only oracle tree, vendored pinned schemas with digests, and per-run evidence directories under `tests/e2e/results/<run-id>/` (git-ignored)

**Testing**: The feature *is* the test system. Self-verification is the mutation suite: planted defects must fail the owning validator for the declared reason

**Target Platform**: Linux and macOS developer machines and CI runners; no container runtime required (none installed locally)

**Project Type**: Single project — a bash/jq CLI tool plus its test system

**Performance Goals**: Offline layer (including existing smoke coverage) under 3 minutes wall clock; no network in the offline layer

**Constraints**: Generation must stay deterministic, offline and model-free; the oracle must be unwritable by the process under test; live model runs have no default time/token/cost ceiling (clarified) but must report progress and consumption; concurrent runs must not collide on workspaces, ports, or harness state; a fresh temp workspace is untrusted by Codex and Claude Code, so project trust and MCP approval must be seeded into the per-run isolated user config before any probe runs (verified mechanism in research D11)

**Scale/Scope**: 5 suites, 1 base fixture + ~6 variants, 2 local MCP services, 3 target harnesses (Devin deferred to structural-only), ~60 functional requirements, ~20 mutation cases

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | How this design satisfies it | Status after Phase 1 |
|---|---|---|
| I. Deterministic Generation | Generation runs from a frozen resolved-input snapshot; the offline layer never invokes a model or the network; repeat-generation and cross-workspace comparison are explicit checks (`offline/idempotence`, `offline/portability`) | PASS |
| II. No Silent Loss of Intent | Every inventory entry resolves to preserved / verified-compensated / approved-gap / failed / unverified; an entry with no outcome fails the run; approved gaps carry a native-equivalent field and stay counted as parity losses in `summary.gaps` | PASS |
| III. Evidence-Backed Harness Compatibility | Claim kinds are recorded per check: `official-schema` (opencode, vendored with digest), `harness-loader-probe` (Codex `--strict-config`, `doctor --json`, `mcp list`; opencode `debug config`, `mcp list`), `local-structural` (Devin, Codex TOML shape). Devin claims recorded `unverified` | PASS |
| IV. Independent Validation (NON-NEGOTIABLE) | The oracle tree lives in the source repo and is never copied into the workspace; the workspace is a separate git repo in a temp dir; the oracle is digest-verified before and after every live phase and made read-only for its duration | PASS |
| V. Real End-to-End Coverage | The live suite installs via `install.sh` in copy mode and invokes the skill through `claude -p`, proving discovery and invocation from stream-json events plus the fixture's own hook audit log | PASS |
| VI. Observable Intent Checks | Intent probes use deterministic harness interfaces first (`codex debug prompt-input`, `codex mcp list`, hook audit logs); model-driven scenarios use fixed trial counts and pre-declared thresholds and preserve every attempt | PASS |
| VII. Reproducibility and Isolation | Pins file records harness, dependency and schema versions plus digests; isolation via `CODEX_HOME`, `HOME`+`XDG_*` and `CLAUDE_CONFIG_DIR` (all three probe-verified); project trust seeded only into the per-run config and recorded; unique workspaces and ports; failure retention with redaction; cleanup restricted to run-created paths | PASS (one recorded deviation, below) |
| VIII. Honest Test Outcomes (NON-NEGOTIABLE) | Five run states are distinct in the result schema; full mode exits nonzero on any blocked/skipped mandatory check; offline-only runs are labelled and cannot print a full-E2E verdict; retries append attempts and never clear a security failure | PASS |
| IX. Regression-Detecting Tests | The mutation suite is a first-class layer with a declarative registry: each case names the validator that must fail and the reason it must fail for | PASS |
| X. Controlled Change and Maintainability | No hand edits to generated artifacts anywhere in the flow; adding a target harness means adding one probe adapter plus its pins entry; the spec-pack `harness_version` field lands with the emitter evidence that uses it | PASS |

**Gate result**: PASS. One deviation is recorded in Complexity Tracking (no
default ceiling on live model runs), authorised by the clarification session and
compensated by mandatory progress and consumption reporting.

## Project Structure

### Documentation (this feature)

```text
specs/001-e2e-test-system/
├── plan.md              # This file
├── research.md          # Phase 0 output — probed interfaces, decisions, evidence
├── data-model.md        # Phase 1 output — entities and their fields
├── quickstart.md        # Phase 1 output — how to run and what to expect
├── contracts/           # Phase 1 output
│   ├── cli.md                       # tests/e2e/run.sh command contract
│   ├── results.schema.json          # machine-readable run result
│   ├── capability-inventory.schema.json  # the oracle's capability records
│   ├── mutation-registry.schema.json     # planted defects and their expected failures
│   └── probe-adapter.md             # contract every harness probe adapter implements
├── checklists/
│   └── requirements.md  # spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
tests/
├── smoke.sh                          # unchanged; called by the offline layer
└── e2e/
    ├── run.sh                        # the single documented entry point
    ├── lib/                          # shared bash helpers
    │   ├── workspace.sh              # temp repo creation, fixture copy, cleanup
    │   ├── isolate.sh                # CODEX_HOME / HOME+XDG / CLAUDE_CONFIG_DIR sandboxing
    │   ├── trust.sh                  # seeds per-harness project trust + MCP approval
    │   ├── install.sh                # runs ../../install.sh, verifies placement, digests
    │   ├── ports.sh                  # collision-safe port allocation and recording
    │   ├── evidence.sh               # evidence dirs, redaction, digest manifests
    │   ├── result.sh                 # emits results.json, enforces state accounting
    │   ├── report.sh                 # renders report.md from results.json
    │   ├── oracle.sh                 # oracle digest + read-only enforcement
    │   ├── prereq.sh                 # prerequisite checks, exit 5
    │   └── assert.sh                 # check registration, states, reason strings
    ├── suites/
    │   ├── offline/                  # deterministic artifact validation (+ smoke.sh)
    │   ├── mutation/                 # planted-defect self-verification
    │   ├── live/                     # real Claude Code skill execution
    │   ├── conformance/              # harness loader probes
    │   └── intent/                   # behavioural scenarios
    ├── probes/                       # one adapter per harness
    │   ├── claude.sh  codex.sh  opencode.sh  devin.sh
    ├── fixtures/
    │   ├── complete-claude/          # committed base fixture (canonical config)
    │   ├── variants/<name>/          # overlay directories applied over the base
    │   └── services/                 # local MCP servers, hook scripts, audit sinks
    ├── oracle/                       # READ-ONLY to everything under test
    │   ├── capabilities.json         # versioned capability inventory
    │   ├── expected-artifacts.json   # independent artifact inventory
    │   ├── expectations/<harness>/   # per-target expected content assertions
    │   ├── approved-gaps.json        # reviewed gap ids and dispositions
    │   ├── scenarios/                # intent scenarios with pre-declared outcomes
    │   └── mutations.json            # mutation registry
    ├── schemas/                      # vendored official schemas + provenance/digests
    ├── pins/                         # pinned harness, dependency, schema versions
    ├── tools/                        # python3 validators (parse, schema, digest, compare, redact)
    └── results/                      # per-run evidence (git-ignored)
```

**Structure Decision**: Single project. The test system is a self-contained
subtree under `tests/e2e/` so `tests/smoke.sh` keeps working exactly as it does
today and remains callable standalone. Bash drives the flow to match the
repository's existing idiom; Python 3 (stdlib, plus a pinned `jsonschema` for
official-schema checks) does the parsing, digesting and comparison work that bash
and `jq` alone cannot do honestly. The `oracle/` tree is the one directory the
generating agent must never write, and it is never copied into the workspace.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| No default time/token/cost ceiling on live model runs (tension with Principle VII's bounded process lifetimes) | Decided in clarification: the operator owns the spend and does not want the suite cutting runs short | A default ceiling was rejected by the user; compensated by mandatory progress reporting, per-scenario consumption accounting, opt-in ceilings, and bounded lifetimes still enforced for fixture services and child processes |

### Exception record (Constitution, Governance § Exception process)

| Field | Value |
|---|---|
| Principle and clause | VII. Reproducibility and Isolation — "Child processes MUST be bounded and terminated" |
| Scope | Live model invocations only (`--suite live`, `--suite intent`). Fixture services, MCP servers and every other child process remain bounded and terminated unconditionally |
| Rationale | The operator owns the spend and asked for no default cut-off; a wall-clock ceiling on a model run also risks recording a truncation as a substantive failure |
| Evidence | Clarification session 2026-09-06, question 3, answer "unbound" |
| Compensating measure | Consumption (elapsed, tokens, cost) measured and reported for every scenario; progress and running consumption surfaced during the run; opt-in `--timeout` and `--ceiling-usd`; a reached ceiling is reported as failed with the limit named |
| Ends when | An operator asks for a default ceiling, or a live run is observed hanging without being noticed — whichever comes first. Reviewed at the next release or when a target harness is added |
| Approver | Repository maintainer (rijojohn), recorded in the clarification session |

The second row below is not an exception: a bootstrap-time dependency does not
violate a principle, and the offline gate still runs with no network.
| A Python dependency (`jsonschema`) beyond the repository's bash+jq baseline | Official-schema validation of opencode's published schema cannot be done honestly with jq structural checks | Hand-rolling a schema validator would produce a check we could not label as schema validation; absence of the dependency blocks that check rather than silently degrading it |
