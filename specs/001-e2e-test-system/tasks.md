---

description: "Task list for the Loom end-to-end test system"
---

# Tasks: End-to-End Test System for Loom

**Input**: Design documents from `/specs/001-e2e-test-system/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/)

**Tests**: This feature *is* a test system, so there is no separate test-of-the-test phase. Its self-verification lives in User Story 2 (the mutation suite), which is the task that proves every validator built in User Story 1 can actually fail.

**Organization**: Tasks are grouped by user story so each layer of the suite can be built, run and demonstrated on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US5)
- Paths are repository-relative, per the structure in plan.md

## Path Conventions

Single project. The test system lives under `tests/e2e/`; `tests/smoke.sh` is
called but never modified. Loom's own sources (`loom.sh`, `lib/`, `install.sh`,
`harness-specs/`, `skills/`) are touched only where a task says so.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Directory skeleton, entry point shell, pinned inputs

- [X] T001 Create the directory skeleton `tests/e2e/{lib,suites/{offline,mutation,live,conformance,intent},probes,fixtures/{complete-claude,variants,services},oracle/{expectations,scenarios},schemas,pins,tools,results}` with `.gitkeep` files where a directory would otherwise be empty
- [X] T002 [P] Add `tests/e2e/results/` and `tests/e2e/.venv/` to `.gitignore`
- [X] T003 Create `tests/e2e/run.sh` implementing argument parsing, `--help` and `--list` exactly as specified in `specs/001-e2e-test-system/contracts/cli.md`, with exit codes 0–5 wired to named error paths and no suite logic yet
- [X] T004 [P] Implement `--bootstrap` in `tests/e2e/run.sh` to create `tests/e2e/.venv` and install the pinned `jsonschema`, writing the resolved version into `tests/e2e/pins/dependencies.json`
- [X] T005 [P] Create `tests/e2e/pins/harnesses.json` recording the pinned versions (claude 2.1.263, codex 0.153.4, opencode 1.18.29) and, per harness, the list of interfaces the probes rely on (from research.md D1)
- [X] T006 [P] Vendor the opencode config schema to `tests/e2e/schemas/opencode.config.schema.json` and record source URL, version, retrieval date and SHA-256 in `tests/e2e/pins/schemas.json`
- [X] T007 [P] Implement `tests/e2e/lib/prereq.sh` checking bash 5+, git, jq, python3 3.11+, the bootstrapped venv, selected harness CLIs and live credentials, reporting each individually and exiting 5 only when a *selected* suite needs the missing item
- [X] T008 [P] Create `tests/e2e/README.md` stub pointing at `specs/001-e2e-test-system/quickstart.md` as the run guide
- [X] T009 Verify `tests/smoke.sh` still passes unmodified after the skeleton lands (baseline for FR-005)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Workspace, isolation, trust, installation, fixtures, the oracle and the result model — everything every suite needs

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Runner core

- [X] T010 Implement `tests/e2e/lib/workspace.sh`: create `/tmp/loom-e2e-<timestamp>-<pid>-<n>` with collision-safe suffixing, copy the fixture preserving dotfiles and executable bits, `git init`, refuse any symlink back to the checkout, and record `workspace.json` per data-model.md
- [X] T011 Implement `tests/e2e/lib/isolate.sh`: point `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME`, `CODEX_HOME` and `CLAUDE_CONFIG_DIR` at `<results-dir>/<run-id>/home/` (not `/tmp`, per research D11), scrub every other environment variable for harness children, and pass through only named credential variables
- [X] T012 Implement `tests/e2e/lib/trust.sh` implementing `seed_trust` per research D11: write `[projects."<ws>"] trust_level = "trusted"` into `$CODEX_HOME/config.toml`, and `projects["<ws>"]` with `hasTrustDialogAccepted`, `enabledMcpjsonServers` and `hasClaudeMdExternalIncludesApproved` into `$CLAUDE_CONFIG_DIR/.claude.json`; assert the target path is inside the run directory before writing, and record what was seeded into `workspace.json`
- [X] T013 [P] Implement `tests/e2e/lib/ports.sh` allocating ports by binding port 0, recording each in `resolved-input.json`, guaranteeing uniqueness across concurrent runs
- [X] T014 Implement `tests/e2e/lib/install.sh`: run the repository `install.sh` in copy mode into the workspace, verify installed contents and locations, capture the source revision and a SHA-256 digest over the installed working-tree files including uncommitted changes, and exercise reinstall preservation and a custom `--tools-dir`/`--skills-dir` path (FR-020, FR-023)
- [X] T015 [P] Implement `tests/e2e/lib/evidence.sh`: per-check evidence directories, digest manifests, and a redaction pass that refuses to write a file matching a credential pattern (FR-026)
- [X] T016 Implement `tests/e2e/lib/result.sh` emitting `results.json` against `specs/001-e2e-test-system/contracts/results.schema.json`, computing `verdict` from check states so a pass cannot be asserted by hand, and refusing a full-E2E verdict when only some layers ran (FR-004, FR-053)
- [X] T017 [P] Implement `tests/e2e/lib/assert.sh` providing check registration with id, suite, mandatory flag, state, reason, claim kind, interface, observed harness version, `pinned` flag and attempt list
- [X] T018 [P] Implement `tests/e2e/lib/report.sh` rendering `report.md` from `results.json`: capability ids mapped to assertions, versions, evidence paths, and separate totals for passed / failed / approved-gap / skipped / blocked (FR-056)
- [X] T019 Implement oracle integrity in `tests/e2e/lib/oracle.sh`: SHA-256 manifest of `tests/e2e/oracle/` taken before and after every live phase, `chmod -R a-w` for the duration, and exit code 4 on any difference (FR-015, research D5)

### Python validators

- [X] T020 [P] Implement `tests/e2e/tools/parse.py` using stdlib `json` and `tomllib` to parse generated artifacts properly and emit a normalised structure for comparison (FR-034)
- [X] T021 [P] Implement `tests/e2e/tools/schema_validate.py` running the vendored schema through the pinned `jsonschema`, recording claim kind `official-schema` with the schema digest, and reporting **blocked** (never skipped, never passed) when the venv is absent (FR-035)
- [X] T022 [P] Implement `tests/e2e/tools/digest.py` producing stable tree digests for the workspace, the fixture and the oracle
- [X] T023 [P] Implement `tests/e2e/tools/compare.py` for byte comparison of two generation outputs and for cross-workspace comparison that normalises only the fields listed in `resolved-input.json.ephemeral_fields`, recording that it normalised them (FR-038, FR-039)

### Fixture

- [X] T024 Author the base fixture `tests/e2e/fixtures/complete-claude/` for pinned Claude Code 2.1.263: `CLAUDE.md` importing `AGENTS.md`, `AGENTS.md` with explicit relationships, `.mcp.json` (HTTP + stdio servers), `.claude/settings.json` with allow/deny/ask permissions and multiple hook events with matchers, scoped rules, and policy documents (FR-007)
- [X] T025 [P] Author fixture skills and agents: at least two skills under `.claude/skills/*/SKILL.md` with resource files and an executable helper, and at least two agents under `.claude/agents/*.md` (FR-007, FR-011)
- [X] T026 [P] Author the MCP allowlist `agent/policies/allowed-mcp-servers.md` in the fixture, templated so the allocated fixture endpoints appear in the approved-servers table
- [X] T027 [P] Implement the local HTTP MCP service in `tests/e2e/fixtures/services/mcp_http.py` (stdlib only): `initialize`, `tools/list`, `tools/call` with a constant two-tool surface, appending one line per call to an audit log
- [X] T028 [P] Implement the local stdio MCP service in `tests/e2e/fixtures/services/mcp_stdio.py` with the same tool surface
- [X] T029 [P] Implement the fixture hook scripts in `tests/e2e/fixtures/complete-claude/hooks/` — harmless, deterministic, appending ordered entries to an audit log that proves which hook ran and in what order (FR-013)
- [X] T030 Author fixture variants under `tests/e2e/fixtures/variants/`: HTTP-only, stdio-only, transport-override, hook-ordering, paths-with-spaces-and-escaping, empty-configuration, and unsupported-construct — each an overlay over the base, with a manifest declaring what it changes (FR-008)
- [X] T031 [P] Author the negative-case variants in `tests/e2e/fixtures/variants/negative-*/`: URL-less MCP entry with the allowlist active, unapproved MCP name, unapproved endpoint, and invalid source input (FR-009, FR-040)

### Oracle (independently authored — never derived from Loom output)

- [X] T032 Author `tests/e2e/oracle/capabilities.json` against `contracts/capability-inventory.schema.json`: every fixture capability with id, kind, source, intent, per-harness expectation, scenarios and required evidence, including skills/agents/rules as `approved-gap` entries carrying `native_equivalent` (FR-010, FR-011, FR-012a)
- [X] T033 [P] Author `tests/e2e/oracle/expected-artifacts.json` as an independent artifact inventory covering adapters, spec packs, `GAPS.md`, the generated manifest and referenced resources, per variant (FR-016)
- [X] T034 [P] Author `tests/e2e/oracle/approved-gaps.json` with exact reviewed gap ids for the permission and hook losses Loom already records, plus the untranslated markdown assets, each with disposition, review date, `native_equivalent` and a `verified_by` that is either a check id or explicitly null (FR-041, FR-055)
- [X] T035 [P] Author per-harness expectation files under `tests/e2e/oracle/expectations/{codex,devin,opencode,claude}/` asserting required content, forbidden content, and unsupported-field rejection for each artifact
- [X] T036 Implement bounded child-process lifetimes in `tests/e2e/lib/workspace.sh`: a trap on EXIT/INT/TERM that terminates fixture services, harness child processes and any orphaned process group the run started, verified by a check that no run-started PID survives the runner (FR-024)

**Checkpoint**: A workspace can be created, isolated, trusted, installed into and torn down; the oracle exists; results can be emitted. User story work can begin.

---

## Phase 3: User Story 1 — Trustworthy offline verdict on every change (Priority: P1) 🎯 MVP

**Goal**: One command produces a deterministic, evidence-backed verdict over a fresh isolated workspace, offline, in under 3 minutes.

**Independent Test**: On a machine with no network and no harness credentials, `tests/e2e/run.sh` exits 0, writes `results.json` and `report.md`, classifies every inventoried capability, and labels itself offline-only.

- [X] T037 [US1] Wire the offline suite driver `tests/e2e/suites/offline/run.sh` into `tests/e2e/run.sh --suite offline`, creating the workspace, installing Loom, generating adapters and freezing `resolved-input.json`
- [X] T038 [US1] Add check `offline.smoke` invoking `tests/smoke.sh` unmodified and recording its result as a single named check (FR-001a, FR-005)
- [X] T039 [P] [US1] Implement `tests/e2e/suites/offline/artifacts.sh`: parse every generated artifact with `tools/parse.py`, validate against `expected-artifacts.json`, and fail on any unexpected file the run produced (FR-037)
- [X] T040 [P] [US1] Implement `tests/e2e/suites/offline/schema.sh` running `tools/schema_validate.py` for opencode, and recording Codex/Devin structural checks honestly as `local-structural` (FR-035, FR-036)
- [X] T041 [P] [US1] Implement `tests/e2e/suites/offline/idempotence.sh`: run apply twice against the frozen `resolved-input.json`, compare bytes, then run `--check` and assert it passes without modifying any file (FR-038)
- [X] T042 [P] [US1] Implement `tests/e2e/suites/offline/portability.sh`: generate in two separate workspaces and assert no absolute temporary path or machine-local value differs, normalising only declared ephemeral fields (FR-039)
- [X] T043 [P] [US1] Implement `tests/e2e/suites/offline/drift.sh`: edit and delete generated artifacts, assert `--check` fails; assert orphan detection via the manifest; assert single-harness generation works (FR-040)
- [X] T044 [P] [US1] Implement `tests/e2e/suites/offline/negative.sh` over the negative variants: invalid source input, unapproved MCP name and endpoint, and a failing emitter that must not partially overwrite valid output (FR-040)
- [X] T045 [US1] Implement `tests/e2e/suites/offline/capabilities.sh` computing one `CapabilityOutcome` per (capability, harness), failing the run when any pair is missing, and enforcing the state rules in data-model.md (approved-gap needs a reviewed gap id; verified-compensated needs a passing `verified_by` check) (SC-002, FR-041)
- [X] T046 [US1] Enforce Devin's deferred status in `tests/e2e/suites/offline/capabilities.sh`: every Devin conformance/behaviour capability resolves to `unverified`, is excluded from pass totals while remaining visible, and is marked non-mandatory so it alone cannot make full mode exit nonzero (FR-043a)
- [X] T047 [US1] Add variant iteration to `tests/e2e/suites/offline/run.sh` so every variant from T030–T031 is generated and validated, with per-variant results recorded in `results.json`
- [X] T048 [US1] Add the offline-only verdict guard: `verdict: offline-pass (offline layer only — not full end-to-end)`, with `verdict_note` required, and assert the word "pass" never appears unqualified in stdout (FR-004)
- [X] T049 [US1] Add check `offline.duration` in `tests/e2e/suites/offline/duration.sh` measuring suite wall clock against the reference runner recorded in `tests/e2e/pins/dependencies.json`: enforced (failing) when `CI=true`, advisory elsewhere (SC-001)
- [X] T050 [US1] Add check `offline.no-network` in `tests/e2e/suites/offline/no-network.sh` asserting the offline layer performs zero network calls — run the layer with outbound access denied and fail if any validator or generator attempts a connection (SC-001, FR-001)
- [X] T051 [US1] Add check `offline.claim-kinds` in `tests/e2e/suites/offline/capabilities.sh` asserting every `preserved` or `verified-compensated` outcome cites an `official-schema`, `harness-loader-probe` or `behaviour-probe` claim kind, so no supported claim rests on format parsing alone (SC-006, FR-035)

**Checkpoint**: The offline gate is real, fast, and honest about what it did not cover.

---

## Phase 4: User Story 2 — Proof that the tests can actually fail (Priority: P2)

**Goal**: Every validator built in US1 is shown to fail on a planted defect, for the declared reason.

**Independent Test**: `tests/e2e/run.sh --suite mutation` applies each registry entry to a throwaway copy and reports a failure when the owning validator does *not* fail, or fails for the wrong reason.

- [X] T052 [US2] Author `tests/e2e/oracle/mutations.json` against `contracts/mutation-registry.schema.json` covering, at minimum: weaken a deny, drop a hook, change an MCP endpoint, omit an expected artifact, corrupt a schema field, hand-edit a generated artifact, delete a generated artifact, orphan an artifact, unapproved MCP name, and invalid source input (FR-042)
- [X] T053 [US2] Implement `tests/e2e/suites/mutation/run.sh`: apply one mutation to a throwaway copy, run only the owning validator, and assert both the failure and that the recorded reason matches `expected_reason_pattern`
- [X] T054 [P] [US2] Add mutation cases in `tests/e2e/oracle/mutations.json` targeting each per-harness expectation file under `tests/e2e/oracle/expectations/` so no harness's validator is unproven
- [X] T055 [P] [US2] Add the oracle-tampering case to `tests/e2e/suites/mutation/oracle-tamper.sh`: a mutation that edits a file under `tests/e2e/oracle/` must be refused or reported as an oracle-integrity failure, never absorbed (FR-014, FR-015)
- [X] T056 [US2] Assert every validator id registered by the offline suite appears as `expected_failing_validator` in at least one mutation case; an unproven validator must not be counted as coverage (FR-042)
- [X] T057 [P] [US2] Add the partial-overwrite mutation in `tests/e2e/suites/mutation/partial-write.sh`: force a `lib/emit-*.sh` failure mid-run and assert no valid artifact was left partially written
- [X] T058 [US2] Guard mutation isolation in `tests/e2e/suites/mutation/run.sh`: each case runs against a workspace copy, with `tests/e2e/tools/digest.py` verifying the committed fixture and repository are unchanged before and after (SC-010)
- [X] T059 [US2] Wire mutation results into `results.json` with `mutation_id` set on every mutation check, per the results schema

**Checkpoint**: A green offline run now means something, because the suite has been shown to go red on demand.

---

## Phase 5: User Story 3 — Evidence that the installed skill really ran (Priority: P3)

**Goal**: Prove Claude Code discovered and invoked the installed skill and ran the installed generator.

**Independent Test**: With credentials, `tests/e2e/run.sh --suite live --keep` retains a transcript showing skill invocation, the generator's own output, the hook audit log, changed files and consumption.

- [X] T060 [US3] Implement `tests/e2e/suites/live/run.sh` invoking Claude Code with `claude -p --output-format stream-json --include-partial-messages --settings … --setting-sources … --add-dir <workspace> --session-id … --debug-file …`, after `seed_trust`
- [X] T061 [US3] Implement the three-signal skill-invocation proof in `tests/e2e/suites/live/evidence.sh`: a Skill event naming `loom`, a tool-use event referencing `agent/tools/loom.sh` plus the generator's `loom: emitted N adapter set(s)` output, and the fixture's hook audit log from the workspace (FR-027, research D4)
- [X] T062 [P] [US3] Capture and record exit status, changed-file set (pre/post digest map), tool and model versions, and per-scenario consumption (elapsed, tokens, cost) into `consumption.json` (FR-028)
- [X] T063 [P] [US3] Implement unbounded-by-default execution with opt-in `--timeout` / `--ceiling-usd`, progress output, and running consumption while the run is in flight (FR-028a)
- [X] T064 [US3] Implement the no-change verification scenario in `tests/e2e/suites/live/no-change.sh`: invoke the skill against an already up-to-date workspace and assert no artifact modification (FR-029)
- [X] T065 [US3] Implement the stale/schema-change scenario: age a spec pack past `spec_pack_max_age_days`, invoke the skill, and record the refreshed pack diff and any emitter diff with its justification (FR-029, FR-031)
- [X] T066 [US3] Freeze the post-skill tool and input snapshot into `resolved-input.json` from `tests/e2e/suites/live/freeze.sh` before repeat-generation checks, so a mid-run tool change cannot read as nondeterminism (FR-031)
- [X] T067 [US3] Call `tests/e2e/lib/oracle.sh` around every live phase (digest before/after, read-only during) from `tests/e2e/suites/live/run.sh`, failing with exit 4 on any change (FR-032)
- [X] T068 [US3] Add check `live.canonical-unchanged` in `tests/e2e/suites/live/canonical.sh` asserting the workspace's canonical config files are unchanged after a live run unless the scenario explicitly permits a change (FR-032)
- [X] T069 [US3] Report the live layer as **blocked** with the missing prerequisite named in `tests/e2e/suites/live/run.sh` when credentials or opt-in are absent, and make `tests/e2e/run.sh` exit 3 in full mode (FR-047, SC-007)

**Checkpoint**: Skill-level end-to-end claims are backed by artefacts the harness produced, not by the test driver's own bookkeeping.

---

## Phase 6: User Story 4 — Confirmation that the target harnesses accept the output (Priority: P4)

**Goal**: Codex and opencode demonstrably load the generated adapters; Devin stays honestly unverified.

**Independent Test**: `tests/e2e/run.sh --suite conformance --harness codex --harness opencode` records the interface used, the version observed, and evidence of the effective loaded configuration.

- [X] T070 [US4] Define the probe adapter interface in `tests/e2e/probes/_adapter.sh` exactly as in `contracts/probe-adapter.md`, including `seed_trust`, `probe_trust_state` and the blocked/unverified return conventions
- [X] T071 [US4] Implement `tests/e2e/probes/codex.sh`: `--version`, `--strict-config`, `doctor --json`, `mcp list --json`, `mcp get`, `debug prompt-input`, `exec --json -C <ws> --sandbox read-only`, with `CODEX_HOME` isolation
- [X] T072 [P] [US4] Implement `tests/e2e/probes/opencode.sh`: `--version`, `debug config`, `debug paths`, `mcp list`, `debug skill`, `agent list`, `run --format json --dir <ws> --port <n> --pure`
- [X] T073 [P] [US4] Implement `tests/e2e/probes/claude.sh` as the source baseline: `mcp list`, `-p --output-format stream-json`, `--safe-mode` negative control, `--permission-prompts none`
- [X] T074 [P] [US4] Implement `tests/e2e/probes/devin.sh` returning `probe_available` blocked and every other function `unverified`, with no invented interface (FR-044, FR-043a)
- [X] T075 [US4] Implement the untrusted-canary check `conformance.<harness>.untrusted-canary` using `--no-trust-seed`: assert Codex returns an empty server list and Claude reports pending approval, and fail the probe if a trust-gated harness still appears to see project configuration (research D11)
- [X] T076 [US4] Implement the customisation-disabled negative control for `probe_loaded_config` and `probe_context_loaded` (`--safe-mode`, `--pure`, project config removed); a canary visible in both runs fails the check
- [X] T077 [US4] Implement unsupported-field rejection checks: `codex --strict-config` against an adapter carrying an unknown field, and opencode schema rejection of the same (FR-036)
- [X] T078 [US4] Implement MCP conformance in `tests/e2e/suites/conformance/mcp.sh`: initialization, tool discovery and one permitted call per harness against `tests/e2e/fixtures/services/`, with services started on allocated ports and terminated afterwards (FR-046)
- [X] T079 [US4] Add `harness_version:` to the front matter of `harness-specs/{claude,codex,devin,opencode}.md` and record the same values in `tests/e2e/pins/harnesses.json` (FR-057a)
- [X] T080 [US4] Implement version-mismatch handling: `--pinned` (CI default) reports the layer blocked; `--advisory` (local default) runs and marks every outcome `pinned: false`, which the results schema forbids counting as verified (FR-057b)
- [X] T081 [US4] Make a mismatch message point at the `loom` skill's Phase A refresh workflow rather than at the expectations (FR-057c)
- [X] T082 [US4] Report blocked with the reason and missing evidence for any unavailable **required** harness in `tests/e2e/suites/conformance/run.sh`, making `tests/e2e/run.sh` exit 3 in full mode; a deferred target (Devin) records `unverified` instead and never triggers exit 3 on its own (FR-047, FR-043a)

**Checkpoint**: Every "supported" claim now cites an interface, a version, and an observation.

---

## Phase 7: User Story 5 — Assurance that the intent survived translation (Priority: P5)

**Goal**: Observable behaviour, not matching syntax — permitted actions work, forbidden ones produce no side effect, hooks fire in order, context influences the task.

**Independent Test**: `tests/e2e/run.sh --suite intent` establishes each scenario's Claude Code baseline first, then judges each target against the manifest with outcomes fixed in advance.

- [X] T083 [US5] Author scenario files under `tests/e2e/oracle/scenarios/` with baseline expectation, per-target expectation, forbidden side effects and (for model-driven scenarios) trial count and threshold fixed in advance (FR-049)
- [X] T084 [US5] Implement `tests/e2e/suites/intent/run.sh`: run the Claude Code baseline first and refuse to judge targets when the baseline does not express the intended behaviour
- [X] T085 [P] [US5] Implement the permitted-call scenario in `tests/e2e/suites/intent/permitted-call.sh`: a permitted documentation MCP call succeeds against the fixture service in each target
- [X] T086 [P] [US5] Implement the forbidden-action scenario in `tests/e2e/suites/intent/forbidden-action.sh`: assert no forbidden side effect on disk, and fail the run permanently on any occurrence regardless of later attempts (FR-051)
- [X] T087 [P] [US5] Implement the protected-file and approval-required scenarios using `--permission-prompts none` (Claude), `--sandbox read-only` (Codex), and opencode without `--auto`
- [X] T088 [P] [US5] Implement the hook-ordering scenario in `tests/e2e/suites/intent/hook-order.sh` reading the fixture audit log: matching hooks run in the intended order, the non-matching hook does not run
- [X] T089 [P] [US5] Implement the context-influence scenario using `codex debug prompt-input` and the Claude stream — deterministic, no model spend where possible (FR-050)
- [X] T090 [US5] Implement bounded repeated trials for model-driven scenarios: preserve every attempt in `attempts[]`, apply the pre-declared threshold, and distinguish a model task failure from a configuration loading or enforcement failure (FR-050)
- [X] T091 [US5] Implement the optional LLM intent reviewer in `tests/e2e/suites/intent/reviewer.sh` reading its rubric from `tests/e2e/oracle/reviewer-rubric.md`, requiring cited trace and artifact references, recording its model and consumption alongside every other live scenario, and marking its output supplementary in `results.json` so it cannot override any deterministic failure (FR-052)
- [X] T092 [US5] Assert skills/agents/rules scenarios resolve to their `approved-gap` dispositions with `native_equivalent` filled from `opencode debug skill` / `agent list`, cross-referencing feature `002-link-context-assets` (FR-012a)

**Checkpoint**: All five layers exist and can be selected, run and reported independently.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T093 [P] Implement the concurrency check: two simultaneous runs complete with distinct workspaces, ports and results directories; serialise the opencode step behind a lock if `/tmp/opencode` proves unsafe (SC-011, research D6)
- [X] T094 [P] Implement retention controls end to end — `--keep`, `--keep-on-failure`, `--clean` — with cleanup confined to run-created paths and a post-run assertion that the committed fixture and oracle are unchanged (FR-025, SC-010)
- [X] T095 [P] Implement the redaction check in `tests/e2e/tools/redact.py`, called by `tests/e2e/lib/evidence.sh`, failing the run rather than writing a file that matches a credential pattern (FR-026, SC-012)
- [X] T096 [P] Add `.github/workflows/e2e-offline.yml` running `tests/e2e/run.sh --suite offline --suite mutation` pinned, credential-free, on every pull request (FR-006)
- [X] T097 [P] Add `.github/workflows/e2e-live.yml` (opt-in, credentialed, `--full`) and `.github/workflows/compat-latest.yml` (latest harness versions, reports drift, never gates) (FR-006, FR-057)
- [X] T098 [P] Write `tests/e2e/README.md` in full: installation, reproducible execution, refreshing upstream pins, extending the fixture and capability inventory, adding a further target harness to the required set, and the gap review process (FR-058)
- [X] T099 [P] Update the repository `README.md` with a testing section describing the layered suites and what each layer does and does not prove
- [X] T100 Update `skills/loom/SKILL.md` Phase A to record `harness_version:` when refreshing a pack, so a future version mismatch is detectable (FR-057a, FR-057c)
- [X] T101 Run `shellcheck` over `tests/e2e/**/*.sh` and fix findings, matching the repository's existing lint discipline
- [X] T102 [P] Establish the oracle-change review convention: add `.github/CODEOWNERS` covering `tests/e2e/oracle/` and document in `tests/e2e/README.md` that any change to expectations, schemas, approved gaps or the intent manifest is a separate, separately justified change, never authored by the process it validates (FR-017)
- [X] T103 Update the Compliance Status list in `.specify/memory/constitution.md` to close the items this feature addresses (Principles II, III, IV, V, VI, VIII, IX) and record any that remain open, in the change that lands them (Constitution, Compliance review)
- [X] T104 [P] Add check `docs.self-coverage` in `tests/e2e/suites/offline/docs.sh` comparing `tests/e2e/run.sh --help` and `tests/e2e/README.md` against the runner's actual option and exit-code table, failing when a flag, suite, exit code or result state is undocumented (SC-013)
- [X] T105 Execute `specs/001-e2e-test-system/quickstart.md` end to end and reconcile any difference between documented and actual behaviour, asserting in particular that `--full` exits 3 only when a mandatory check is blocked or skipped and that a deferred Devin alone does not produce a nonzero exit (FR-059, FR-043a)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup — **blocks all user stories**
- **US1 (Phase 3)**: depends on Foundational
- **US2 (Phase 4)**: depends on US1 — mutation cases target the validators US1 builds
- **US3 (Phase 5)**: depends on Foundational; independent of US1/US2, but shares the workspace and evidence machinery
- **US4 (Phase 6)**: depends on Foundational; independent of US1–US3
- **US5 (Phase 7)**: depends on US4 probes for deterministic behavioural evidence, and on US3 for the Claude baseline path
- **Polish (Phase 8)**: depends on the stories it touches

### User Story Dependencies

- **US1 (P1)**: foundation only — the MVP
- **US2 (P2)**: genuinely depends on US1; a mutation needs a validator to break
- **US3 (P3)**: independent of US1/US2
- **US4 (P4)**: independent of US1–US3
- **US5 (P5)**: depends on US3 and US4

### Parallel Opportunities

- Setup: T002, T004, T005, T006, T007, T008 in parallel
- Foundational: the Python validators (T020–T023), the fixture services and hooks (T027–T029), and the oracle files (T033–T035) are three independent parallel groups
- US1: T039–T044 plus T050 are separate suite files and run in parallel after T037–T038; T051 extends T045's file and follows it
- US4: T072, T073, T074 (three probe adapters) in parallel after T070–T071
- US5: T085–T089 in parallel after T083–T084
- Polish: T093–T099, T102 and T104 in parallel

---

## Parallel Example: Foundational

```bash
# Python validators together (different files, no shared state):
Task: "Implement tests/e2e/tools/parse.py"
Task: "Implement tests/e2e/tools/schema_validate.py"
Task: "Implement tests/e2e/tools/digest.py"
Task: "Implement tests/e2e/tools/compare.py"

# Fixture services and hooks together:
Task: "Implement tests/e2e/fixtures/services/mcp_http.py"
Task: "Implement tests/e2e/fixtures/services/mcp_stdio.py"
Task: "Implement tests/e2e/fixtures/complete-claude/hooks/"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 Setup → Phase 2 Foundational → Phase 3 US1
2. **STOP and VALIDATE**: `tests/e2e/run.sh` exits 0 offline in under 3 minutes, classifies every capability, and labels itself offline-only
3. This alone replaces the current situation, where nothing verifies Loom beyond `tests/smoke.sh`

### Incremental Delivery

1. + US2 → a green run now means something, because the validators are proven to fail on demand
2. + US3 → the constitution's Principle V gap closes: the installed skill is actually exercised
3. + US4 → "supported" claims stop being assumptions
4. + US5 → semantics, not just syntax
5. + Polish → CI separation, docs, concurrency, redaction

### Notes

- Do not weaken an expectation to make an existing emitter pass; a failing expectation is a finding, not a bug in the test (FR-060)
- Translator feature expansion stays out of scope; skills/agents/rules remain approved gaps here and are addressed by feature `002-link-context-assets` (FR-061)
- `tests/smoke.sh` is called, never edited
- Commit after each task or logical group

---

## Phase 9: Convergence

- [X] T106 Reconcile `intent.approval-required` and `intent.protected-file` with the oracle's reviewed-gap dispositions: record `approved-gap` (with the exact `gap.codex.ask-push`, `gap.opencode.ask-push`, `gap.codex.deny-readenv`, `gap.opencode.deny-readenv` ids) for targets whose capabilities the inventory dispositions as gaps — mirroring `hook-order.sh` — and keep permanent failure only for actual forbidden side effects on capabilities claimed supported and for the Claude baseline per Constitution II/VIII, FR-048 (contradicts)
- [X] T107 Re-run `--suite live` and `--suite intent` with valid credentials and reconcile full-mode acceptance (`--full` reaching `full-e2e-pass` or honest blocked outcomes): the only full run on record failed 12 mandatory checks (live-1 OAuth expiry, 0/2 Claude baseline trials, hook-order baseline missing entries, conformance.claude failures) and no `full-e2e-pass` exists per FR-059, T105, SC-007, SC-008 (partial)
- [X] T108 Make the materialized stdio MCP fixture actually run: `materialize.sh` writes `docs-local` args `["-u","services/mcp_stdio.py"]` but `mcp_stdio.py` requires an audit-log `argv[1]`, so the server crashes with `IndexError` in every live/intent Claude session ("docs-local failed" in retained transcripts) per FR-007, FR-013, T028 (partial)
- [X] T109 Make the post-run pristine check effective before the feature's first commit: `run.pristine` relies on `git status --porcelain` of tracked files and cannot detect fixture/oracle modification while `tests/e2e/` is untracked; add digest-based fixture/oracle verification for the suites that lack it per SC-010, T094 (partial)
- [X] T110 Fix `quickstart.md` inconsistencies: §1 prose says "9 approved gaps" and "6 unverified Devin entries" against the sample block's 45 and 7, and align §8's lock-or-safe wording with the actual concurrency arrangement per T105 (partial)
- [X] T111 Create `tests/e2e/suites/conformance/mcp.sh` per T078 or record the deliberate decision to fold MCP conformance into `conformance/run.sh` plus the probe adapters (partial)
- [X] T112 Make redaction refusals fail the run, not just skip retention: `retain_file` refuses credential-matching writes but `T095` specifies failing the run, and no end-of-run scan of retained evidence exists per T095, SC-012 (partial)

---

## Phase 10: Convergence

- [X] T113 Constrain the `evidence.redaction` check's suite to the results-schema enum: `lib/evidence.sh` derives `suite` from the check-id prefix and can emit `run` (or any out-of-enum suite) for non-suite-prefixed ids, violating `contracts/results.schema.json`'s `check.suite` enum `["offline","mutation","live","conformance","intent"]` if results are ever validated; fall back to a schema-valid suite (e.g. the first selected suite from `E2E_SUITES`) per contracts/results.schema.json, T112 (partial)
