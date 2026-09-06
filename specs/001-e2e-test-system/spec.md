# Feature Specification: End-to-End Test System for Loom

**Feature Branch**: `001-e2e-test-system`

**Created**: 2026-09-06

**Status**: Draft

**Input**: User description: "Build an end-to-end test system for Loom, which installs a Claude Code skill and deterministically translates canonical Claude Code project configuration into Codex, Devin, and opencode adapters. Extend the existing tests/smoke.sh coverage while retaining its fast, offline execution." (full brief: `docs/e2e-speckit-prompt.md`)

## Clarifications

### Session 2026-09-06

- Q: Devin runs as a hosted service with no local CLI — how should a full run treat Devin conformance? → A: Ignore Devin for now, to be added later. Devin adapters are still generated and validated by the offline layer; Devin conformance and behavioural claims are reported as unverified (never passed), and Codex plus opencode are the required targets for the live layers.
- Q: What disposition should skills, agents, scoped rules and context semantics get, given the emitters do not translate them? → A: Verified that no emitter links or copies them today (only the context path is referenced). They are inventoried as approved gaps for this feature, each ledger entry must record whether the target has a native equivalent, and wiring them into targets is specified separately as feature `002-link-context-assets`.
- Q: What upper bound should a single live Claude Code run be allowed to consume before it is cut off? → A: Unbound. No default time, token or cost ceiling is imposed on live runs; consumption is measured and reported as evidence, and limits remain available as opt-in settings.
- Q: How should the new suite relate to the existing `tests/smoke.sh`? → A: Option A — one new entry point owns layer selection and invokes the existing smoke coverage as part of its offline layer; `tests/smoke.sh` keeps working standalone and unchanged, and new offline checks are added beside it.
- Q: What should happen when the harness version found at runtime does not match the pinned one? → A: Option C — CI gating requires the exact pinned versions and reports BLOCKED on mismatch; local runs proceed against the installed version but are labelled unpinned/advisory and cannot be cited as gate evidence. Additionally: spec packs carry no harness version today (only `generated:`/`status:`), so the version each pack was verified against MUST be recorded, making mismatch detectable and routing it to the skill's existing Phase A refresh.

## User Scenarios & Testing *(mandatory)*

The audience for this feature is the Loom maintainer and any reviewer who must
decide whether a change to Loom is safe to merge. "The system" below means the
test system being specified, not Loom itself.

### User Story 1 - Trustworthy offline verdict on every change (Priority: P1)

A maintainer changes an emitter and runs the test system's fast offline suite
before opening a pull request. The system copies a committed, realistic canonical
fixture into a fresh isolated workspace, installs Loom from the working checkout
(including uncommitted changes), generates adapters, and judges every produced
artifact against an independently authored expectation set. Within a couple of
minutes the maintainer gets a verdict that names each capability, the state it
ended in for each target, and where the evidence lives.

**Why this priority**: This is the layer that runs on every change and the only
layer that needs no credentials, no network, and no model. It also carries the
fixture, the capability inventory, the independent oracle, the isolation
machinery, the entry point, and the report format that every later layer reuses —
nothing else can be built until it exists.

**Independent Test**: Run the offline suite alone against the current checkout on
a machine with no harness credentials and no network. It must complete, produce a
machine-readable result file plus a human report, correctly classify the known
capabilities of the base fixture, and clearly label itself as offline-only rather
than as full end-to-end success.

**Acceptance Scenarios**:

1. **Given** a clean checkout, **When** the maintainer runs the offline suite,
   **Then** a fresh isolated workspace is created, Loom is installed into it from
   the working checkout, adapters are generated, every generated artifact is
   validated against the independent expectation set, and the run reports pass
   with the recorded source revision and working-tree digest.
2. **Given** the offline suite has completed successfully, **When** the maintainer
   reads the report, **Then** every capability in the versioned inventory appears
   exactly once with a state of preserved, verified-compensated, approved-gap,
   failed, or unverified, and approved gaps are counted as parity losses rather
   than folded into the pass total.
3. **Given** an emitter change that drops a permission entry from one target's
   adapter, **When** the offline suite runs, **Then** the run fails and names the
   capability, the target, and the specific missing expectation.
4. **Given** a successful offline run, **When** generation is run a second time
   over the same frozen inputs and the verification mode is run afterwards,
   **Then** the second generation is byte-identical to the first and verification
   passes without modifying any file.
5. **Given** two offline runs in different workspace directories, **When** their
   generated artifacts are compared, **Then** no absolute workspace path or other
   machine-local value differs between them.
6. **Given** the fixture's committed copy on disk, **When** any suite finishes,
   **Then** the committed fixture is unmodified and the isolated workspace
   contains no link back to the source checkout.

---

### User Story 2 - Proof that the tests can actually fail (Priority: P2)

A reviewer needs to believe a green run. The system deliberately plants defects —
weakens a deny rule, drops a hook, alters an MCP endpoint, omits an expected
artifact, corrupts a schema field, hand-edits and deletes a generated file — and
demonstrates that the relevant validator fails, and fails for the intended reason.

**Why this priority**: A validator that has never been shown to fail is an
assumption, not coverage. This layer is what converts the P1 verdict from a claim
into evidence, and it runs offline so it can gate every change.

**Independent Test**: Run the mutation and negative suite alone. Each planted
defect must produce a failure attributed to the expected validator and the
expected reason; a defect that goes undetected, or that fails for an unrelated
reason, is itself reported as a failure of the test system.

**Acceptance Scenarios**:

1. **Given** a generated artifact that has been hand-edited after generation,
   **When** the verification mode runs, **Then** it fails and identifies the
   edited file.
2. **Given** a generated artifact that has been deleted, and separately a
   generated file that regeneration no longer produces, **When** verification
   runs, **Then** each case fails and is reported as drift and as an orphan
   respectively.
3. **Given** a planted mutation that weakens a restriction in one target's
   adapter, **When** the suite runs, **Then** the validator that owns that
   capability fails, and the recorded reason matches the reason declared for that
   mutation in advance.
4. **Given** invalid canonical input, a canonical server or endpoint absent from
   the approved allowlist, or a target-specific emitter failure, **When**
   generation runs, **Then** it exits nonzero, states the cause, and leaves no
   partially overwritten valid artifact behind.
5. **Given** a mutation of a validator's own expectation file rather than of an
   artifact, **When** the suite runs, **Then** the change is refused or reported,
   because expectations are not writable by the process under test.

---

### User Story 3 - Evidence that the installed skill really ran (Priority: P3)

A maintainer opts into a live run. The system installs Loom into the isolated
workspace, drives real Claude Code, and records that Claude Code discovered the
installed skill, invoked it, followed its workflow, and ran the installed
generator — not that a script was called directly.

**Why this priority**: Installation, discovery and invocation are the seams users
actually hit, and no offline check exercises them. It is below P1 and P2 because
it costs money, needs credentials, and is not deterministic.

**Independent Test**: Run the live skill suite alone with credentials present.
It must retain a transcript or structured event record showing skill discovery
and invocation, the exit status, the set of changed files, the tool and model
versions used, and the time, tokens and cost consumed.

**Acceptance Scenarios**:

1. **Given** credentials and an opt-in flag, **When** the live skill suite runs,
   **Then** the retained evidence shows the installed skill being discovered and
   invoked by Claude Code, the installed generator being executed, the resulting
   changed-file set, and the time, tokens and cost the run consumed.
2. **Given** an already up-to-date workspace, **When** the skill is invoked for a
   no-change verification scenario, **Then** the run reports no required change
   and produces no artifact modification.
3. **Given** a deliberately stale specification pack or a changed target schema,
   **When** the skill is invoked, **Then** the run performs the refresh, and any
   emitter change it makes is recorded as a diff with its justification.
4. **Given** a completed skill run, **When** repeat-generation checks execute,
   **Then** they run against a frozen snapshot of the post-skill tools and inputs,
   so a mid-run tool change cannot be mistaken for nondeterminism.
5. **Given** a skill run in progress, **When** it attempts to modify validators,
   expectation sets, the intent manifest, or the canonical source configuration
   outside an explicitly permitted scenario, **Then** the attempt fails and the
   run is reported as failed.
6. **Given** no credentials or no opt-in, **When** full mode is requested,
   **Then** this layer is reported as blocked with the missing prerequisite named,
   and the overall run exits nonzero.

---

### User Story 4 - Confirmation that the target harnesses accept the output (Priority: P4)

A maintainer needs to know that Codex and opencode actually load the
generated adapters — that the configuration is trusted, the fields are recognised,
and project files are not silently ignored in favour of user-level settings.

**Why this priority**: A file that parses is not a file that loads. This is the
difference between a claim and a verified claim, but it depends on external tools
and access, so it cannot gate every change.

**Independent Test**: Run the harness conformance suite alone with the target
tooling available. For each target it must record the interface used, the target
version, and observed evidence of the effective loaded configuration — not merely
a zero exit status.

**Acceptance Scenarios**:

1. **Given** an available target harness, **When** conformance runs, **Then** the
   system uses that harness's documented validation or startup interface, records
   the interface and version, and reports whether the project configuration was
   loaded and honoured.
2. **Given** a canary setting placed in the project configuration, **When** the
   target harness starts, **Then** the observed behaviour confirms the project
   file was read and was not overridden by user-level configuration or blocked by
   trust gating; if it was, the run fails and says which.
3. **Given** an adapter containing a field the target does not support, **When**
   conformance runs, **Then** the unsupported field is detected and reported
   rather than silently accepted.
4. **Given** the local fixture MCP services, **When** a target harness starts,
   **Then** MCP initialization, tool discovery, and a permitted call are observed
   to succeed against those services, including for a target that does not share
   the host's network namespace.
5. **Given** a target harness that is unavailable, unlicensed, or requires remote
   access that is not configured, **When** full mode runs, **Then** that target is
   reported as blocked with the reason and the missing evidence named, and the run
   exits nonzero.
6. **Given** an official schema for a target, **When** validation runs, **Then**
   the schema's source, version, retrieval date and digest are recorded; where no
   official schema exists, the check is labelled a local structural check and the
   corresponding claim is not reported as schema-validated.

---

### User Story 5 - Assurance that the intent survived translation (Priority: P5)

A maintainer wants to know that meaning, not just syntax, crossed the boundary:
that a permitted action still succeeds, a forbidden one produces no forbidden
side effect, an approval-gated action cannot run silently, hooks fire in order for
matching events and stay silent for non-matching ones, and any context, rule,
skill or agent semantics claimed as supported demonstrably influence the task.

**Why this priority**: This is the deepest claim Loom makes and the most expensive
to verify. It builds on every earlier layer and is partly model-driven, so it
lands last.

**Independent Test**: Run the intent suite alone. Each scenario must first be
shown to express the intended behaviour in Claude Code as the source baseline,
then evaluated against the independent manifest for each target, with outcomes
defined before execution.

**Acceptance Scenarios**:

1. **Given** a scenario whose expected outcome was fixed in advance, **When** it
   runs in Claude Code, **Then** the baseline behaviour is observed and recorded
   before any target is judged.
2. **Given** a permitted documentation call and a forbidden action, **When** each
   runs in a target harness, **Then** the permitted call succeeds and the
   forbidden action produces no forbidden side effect.
3. **Given** a protected-file edit and an approval-required action, **When** each
   is attempted, **Then** the edit is blocked and the approval-required action
   does not execute without approval.
4. **Given** a matching and a non-matching hook event, **When** each occurs,
   **Then** the matching hooks run in the intended order and write their audit
   record, and the non-matching hook does not run.
5. **Given** a model-driven scenario, **When** it runs, **Then** it uses bounded
   repeated trials against a threshold fixed in advance, preserves every attempt,
   and distinguishes a model task failure from a configuration loading or
   enforcement failure.
6. **Given** any observed forbidden side effect, **When** later attempts succeed,
   **Then** the run still fails; a retry never clears a security-relevant failure.
7. **Given** a model-based reviewer opinion, **When** it conflicts with a failed
   schema check, a missing probe, an observed forbidden side effect, or an
   unsupported capability, **Then** the deterministic result stands and the
   opinion is recorded as supplementary only.

---

### Edge Cases

- Two runs start concurrently on the same machine: workspaces, ports and audit
  logs must not collide, and neither run may clean up the other's paths.
- A run is interrupted or a child process hangs: process lifetimes are bounded,
  children are terminated, and the partially completed run is reported as failed
  or blocked rather than silently abandoned.
- A run fails: its workspace and logs are preserved under the retention controls,
  with credentials redacted, and cleanup touches only paths the run created.
- Canonical configuration contains paths with spaces, characters requiring
  escaping in a target's format, or an empty configuration section: the generated
  artifacts remain valid and the expectations cover these cases explicitly.
- Canonical configuration contains a construct no target supports, or an input the
  current implementation rejects (for example an MCP entry with no URL while the
  allowlist gate is active): these are exercised as declared negative cases, not
  left to make the base fixture unrunnable.
- The canonical configuration expresses capabilities the current emitters do not
  translate at all (skills, agents, scoped rules, parts of context): each must
  resolve to native support with evidence, an approved gap, or a failure — never
  to silence.
- A target harness emits a dynamic value (an ephemeral endpoint or port) into an
  artifact: repeatability comparisons use identical resolved inputs, or normalise
  only fields designated ephemeral in advance, and the normalisation is recorded.
- Only offline layers ran: the result must never be presented as full end-to-end
  success, in any summary, exit status or report line.
- An approved-gap allowance is present: it must reference an exact reviewed gap
  identifier, so a new unrelated regression cannot be absorbed by a broad
  expected-failure rule.
- Upstream harness versions or published documentation change without any change
  in this repository: the gating suites, which are pinned, must be unaffected, and
  the change must surface only in the separately labelled compatibility job.

## Requirements *(mandatory)*

### Functional Requirements

**Suite structure and entry point**

- **FR-001**: The system MUST provide one documented local entry point that
  selects among at least four separable layers: fast offline deterministic checks,
  live skill execution, target harness conformance, and behavioural intent probes.
- **FR-001a**: The existing smoke coverage MUST be invoked by the offline layer of
  that entry point rather than rewritten, MUST remain runnable standalone and
  unchanged, and MUST keep its own pass or fail contribution visible in the
  report. New offline checks MUST be added beside it, not folded into it.
- **FR-002**: The entry point MUST offer a full mode that requires every mandatory
  layer, plus selection of individual layers, selection of target harnesses,
  optional timeouts (unset by default), and retention controls for workspaces and
  logs.
- **FR-003**: The entry point MUST check its prerequisites before running and MUST
  state precisely which prerequisite is missing when one is.
- **FR-004**: Success in one layer MUST NOT be reported as success in another, and
  an offline-only run MUST NOT be reported as full end-to-end success.
- **FR-005**: The existing fast, offline smoke coverage MUST continue to pass
  unmodified, and the offline layer as a whole MUST remain fast enough to run on
  every change.
- **FR-006**: Continuous integration MUST separate reproducible offline gates from
  credentialed or paid live runs, and live runs MUST be opt-in.

**Fixture and capability inventory**

- **FR-007**: The system MUST include a committed, realistic canonical fixture
  containing a project context file, an agent context file with explicit
  relationships, multiple skills with resources and executable helpers, multiple
  agents, scoped rules, policy documents, an MCP allowlist, MCP server
  definitions, harness settings, multiple hook events with matchers, and allow,
  deny and ask permissions, using valid documented configuration for a pinned
  Claude Code version, with every referenced script and resource present.
- **FR-008**: The fixture MUST be organised as a base fixture plus variants that
  cover HTTP and stdio MCP transports, transport overrides, hook ordering, paths
  with spaces, escaping, empty configuration, and unsupported constructs.
- **FR-009**: Inputs the current implementation rejects MUST be expressed as
  explicit negative cases rather than being removed from coverage or allowed to
  make the base fixture unrunnable.
- **FR-010**: The system MUST define completeness through a versioned capability
  inventory rather than an open-ended promise to support every possible source
  feature; the inventory version MUST appear in every report.
- **FR-011**: Every inventoried capability MUST carry an identifier, its source
  location, its intended behaviour, a per-target expectation, positive and
  negative scenarios, and the evidence required to consider it verified.
- **FR-012**: Capabilities the current emitters do not translate — including
  skills, agents, scoped rules, and context semantics — MUST be inventoried and
  MUST resolve to native or shared support with evidence, an approved gap, or a
  failure; silent loss MUST fail the run.
- **FR-012a**: Each approved-gap entry MUST record whether the target harness has
  a native equivalent for the capability, and where one exists MUST cite the
  evidence for it, so that the ledger reads as a reviewable backlog rather than a
  permanent exemption. Wiring those capabilities into targets is out of scope
  here and is specified separately.
- **FR-013**: Fixture MCP services and hooks MUST be local, deterministic and
  harmless, MUST write observable audit records, and MUST NOT depend on public
  service uptime or on real secrets.

**Independent oracle**

- **FR-014**: The intent manifest, expectation sets, validators, schemas and
  approved-gap definitions MUST be authored independently and MUST NOT be derived
  from Loom's outputs or from the generated gap ledger.
- **FR-015**: These oracle artifacts MUST live outside the workspace that the
  generating agent can write, and the isolation — not an instruction — MUST be
  what prevents modification.
- **FR-016**: An expected inventory of artifacts MUST be maintained independently
  of the generated manifest, so that a missing manifest entry cannot conceal a
  missing output.
- **FR-017**: Changes to oracle artifacts MUST be identifiable as a separate,
  human-reviewed change carrying an explicit justification.

**Isolation, installation and lifecycle**

- **FR-018**: Each run MUST copy the fixture into a fresh uniquely named temporary
  workspace, preserving dotfiles and executable bits, choosing a collision-safe
  name, and MUST initialise that workspace as an independent repository.
- **FR-019**: The workspace MUST NOT link back to the source checkout, and the
  committed fixture MUST NOT be mutated by any run.
- **FR-020**: Each run MUST record the source revision plus a digest of the
  installed working-tree files, including uncommitted changes.
- **FR-021**: Harness user configuration, caches, trust state and environment MUST
  be isolated using each harness's supported mechanisms; only credentials a
  scenario requires may be injected, and copying a developer's home directory or
  credential store is forbidden.
- **FR-022**: The run MUST positively confirm that the harness under test loaded
  project configuration from the workspace rather than from developer state.
- **FR-023**: Loom MUST be installed with the repository installer in copy mode;
  the installed contents and locations MUST be verified, and reinstall
  preservation and custom install paths MUST be exercised.
- **FR-024**: Concurrent runs MUST use unique workspaces and ports; process
  lifetimes MUST be bounded and child processes terminated.
- **FR-025**: Failed runs MUST preserve their workspace and useful logs; keep and
  cleanup controls MUST be explicit and cleanup MUST be confined to paths the run
  created.
- **FR-026**: Credentials and secrets MUST be redacted from retained logs and
  evidence.

**Real skill execution**

- **FR-027**: A skill-level end-to-end claim MUST be backed by evidence that
  Claude Code discovered the installed skill, invoked it, followed its workflow,
  and ran the installed generator; invoking the generator directly MUST NOT
  satisfy this claim.
- **FR-028**: Live runs MUST capture structured events or transcripts, exit
  status, the changed-file set, and tool and model versions, and MUST measure and
  report elapsed time, token usage and cost for each scenario and for the run as a
  whole.
- **FR-028a**: Live runs MUST NOT impose a time, token or cost ceiling by default.
  Ceilings MUST be available as opt-in settings; when one is set and reached, the
  scenario MUST be reported as failed with the limit named. A live run left
  running is the operator's decision, so the suite MUST surface progress and
  accumulated consumption while it runs rather than failing silently.
- **FR-029**: The system MUST cover a no-change verification scenario and a
  controlled stale-or-schema-change scenario that exercises specification refresh
  and justified emitter change.
- **FR-030**: Reproducible scenarios MUST use versioned documentation evidence; a
  separate scenario MUST monitor live upstream documentation for compatibility
  drift without gating reproducible runs.
- **FR-031**: Diffs the skill makes to installed emitters and specification packs
  MUST be recorded, and the post-skill tool and input snapshot MUST be frozen
  before repeat-generation checks run.
- **FR-032**: The skill MUST be prevented from editing validators, expectation
  sets or the intent manifest, and MUST preserve the canonical source
  configuration unless a scenario explicitly and independently permits a change.
- **FR-033**: Model execution MUST be treated as nondeterministic; determinism
  claims apply to generation from frozen inputs, not to the model phase.

**Deterministic artifact validation**

- **FR-034**: Structured artifacts MUST be parsed with real parsers for their
  formats, never by pattern matching over text.
- **FR-035**: Where an official version-matched schema exists, validation MUST use
  it and MUST record the source URL, version, retrieval date and digest; where
  none exists, the check MUST be labelled a local structural check and target
  conformance MUST additionally require native loader evidence.
- **FR-036**: Unsupported or unknown fields in generated artifacts MUST be
  rejected.
- **FR-037**: Validation MUST cover all artifacts — adapter files, refreshed
  specification packs, the gap ledger, the generated manifest, referenced
  resources — and MUST report any unexpected file the run produced.
- **FR-038**: Generation MUST be run twice over identical frozen inputs and the
  generated bytes compared; the verification mode MUST pass without modifying any
  file.
- **FR-039**: Generated output MUST NOT leak absolute temporary workspace paths or
  other machine-local values; this MUST be checked by comparing runs in separate
  workspaces.
- **FR-040**: The system MUST verify that deliberately editing or deleting a
  generated artifact makes verification fail, and MUST cover orphan detection,
  single-target generation, invalid source input, unapproved MCP names and
  endpoints, and failures that must not partially overwrite valid output.
- **FR-041**: Every unrepresentable capability MUST have a precise ledger entry
  with a reviewed disposition; a compensating control counts as verified only when
  a check demonstrates it operating, not when prose describes it.
- **FR-042**: The system MUST include mutation checks that weaken a restriction,
  drop a hook, change an MCP endpoint, omit an expected artifact and corrupt a
  schema field, and MUST confirm the relevant validator fails for the intended
  reason; a validator that cannot be shown to fail on a planted defect MUST NOT
  count as coverage.

**Target harness conformance**

- **FR-043**: Claude Code MUST be exercised as the source baseline. Codex and
  opencode are the required targets for the conformance and intent layers.
- **FR-043a**: Devin is deferred by decision, not by unavailability: its adapters
  MUST still be produced and validated by the offline layer, and its conformance
  and behavioural claims MUST be reported as unverified — never as passed,
  skipped-and-fine, or preserved — until a later change adds Devin as a required
  target. Registering Devin later MUST require only declaring it required and
  supplying its access arrangement, with no change to the fixture, the oracle, or
  the reporting model.
- **FR-044**: The supported validation or startup interface of each target MUST be
  discovered and documented; the system MUST NOT invent command-line interfaces
  nor substitute a format parser for a real harness loader.
- **FR-045**: Conformance MUST verify the effective loaded configuration rather
  than a zero exit status, using harmless canary settings or observable probes to
  detect ignored project files, unknown fields, trust gating and user-level
  overrides.
- **FR-046**: Conformance MUST exercise MCP initialization, tool discovery and
  permitted calls against the local fixture services, with an explicit arrangement
  that lets container-based or remote harnesses reach those services rather than
  assuming a shared local network.
- **FR-047**: When a target requires a remote service, credentials or unavailable
  tooling, the system MUST report blocked or skipped with the reason and the
  missing evidence, and full mode MUST exit nonzero when any required target is
  untested.

**Intent and behavioural validation**

- **FR-048**: Behavioural scenarios MUST test observable effects, including that a
  permitted call succeeds, a forbidden action produces no forbidden side effect,
  protected-file edits are blocked, an approval-required action cannot silently
  execute, matching hooks execute in the correct order while non-matching hooks do
  not, and that rules, context, skills and agents influence their designated task
  wherever support is claimed.
- **FR-049**: Each scenario MUST first establish the intended behaviour in the
  source baseline, then evaluate target behaviour against the independent
  manifest, with expected outcomes defined before execution; matching syntax MUST
  NOT be treated as matching semantics.
- **FR-050**: Deterministic tool or hook probes MUST be preferred wherever a
  harness supports them; model-driven scenarios MUST use bounded repeated trials
  against thresholds fixed in advance, preserve every attempt, and distinguish
  model task failure from configuration loading or enforcement failure.
- **FR-051**: A dangerous or forbidden side effect MUST fail the run immediately,
  and no retry may erase it.
- **FR-052**: A model-based intent reviewer MAY supplement deterministic evidence
  using a structured rubric with cited trace and artifact references, but MUST NOT
  override a failed schema check, a missing probe, a forbidden side effect or an
  unsupported capability.

**Reporting and outcome accounting**

- **FR-053**: Every capability outcome MUST be reported as exactly one of
  preserved, verified-compensated, approved-gap, failed, or unverified, and run
  outcomes MUST distinguish passed, failed, approved-gap, skipped and blocked as
  separately counted states.
- **FR-054**: An approved gap MUST remain visible as a parity loss in every total
  and MUST NOT be netted into a pass count.
- **FR-055**: Approved-gap allowances MUST reference exact reviewed gap
  identifiers; broad or pattern-matched expected-failure rules are forbidden.
- **FR-056**: The system MUST emit machine-readable results and a concise human
  report that map capability identifiers to assertions, and that record harness,
  schema and model versions, evidence paths, gaps, failures and skips.
- **FR-057**: Gating suites MUST pin dependency, schema and harness versions; a
  separate, clearly labelled job MUST check compatibility against latest versions
  without gating reproducible runs.
- **FR-057a**: Each harness specification MUST record the harness version its
  claims were verified against, so a runtime mismatch is detectable; the packs
  record only a generation date today, and adding that version field is in scope
  for this feature.
- **FR-057b**: Every conformance run MUST record the harness version actually
  observed. On a gating run, a mismatch against the pinned version MUST report
  that layer as blocked. On a local run, execution MUST proceed against the
  installed version and every resulting outcome MUST be labelled unpinned and
  advisory; an advisory outcome MUST NOT be cited as gate evidence, counted as a
  verified claim, or reported as a pass in full mode.
- **FR-057c**: A detected version mismatch MUST direct the operator to the
  existing specification-refresh workflow rather than being resolved by editing
  expectations, and the refreshed pack plus any justified emitter change MUST land
  together.

**Documentation and maintenance**

- **FR-058**: Documentation MUST cover installation, reproducible execution,
  refreshing upstream pins, extending the fixture and capability inventory, adding
  a further target harness to the required set, and the gap review process.
- **FR-059**: Acceptance MUST require a demonstrated full run across the required
  targets, explicit blocked status for any required target that is unavailable,
  explicit unverified status for deferred targets, and proof that deliberate
  artifact and behavioural mutations are caught.
- **FR-060**: Expectations MUST NOT be weakened to make existing emitters pass;
  any expectation change MUST carry independent justification.
- **FR-061**: Expanding Loom's translation features MUST remain separate from
  implementing this test system, unless a specific expansion is explicitly
  required and specified.

### Key Entities

- **Capability inventory**: The versioned list that defines what "complete" means.
  Each entry has an identifier, source location, intended behaviour, per-target
  expectation, positive and negative scenarios, and required evidence.
- **Intent manifest**: The independently authored oracle of expected behaviour,
  stored outside the agent-writable workspace, never derived from Loom output.
- **Fixture set**: The committed base canonical configuration plus its variants,
  including local MCP services, hook scripts, skills, agents, rules and policy
  documents, with all referenced resources.
- **Isolated workspace**: A fresh uniquely named temporary repository holding a
  copy of the fixture and an installed Loom, with isolated harness state and
  unique ports; retained on failure.
- **Pin set**: The recorded versions and digests that make a gating run
  reproducible — source revision, working-tree digest, dependency, schema and
  harness versions, fixture revision, and model and tool versions for live runs.
- **Evidence bundle**: The retained transcripts, structured events, probe outputs,
  audit logs, diffs and artifact copies that support each recorded outcome, with
  credentials redacted.
- **Capability outcome**: The per-capability, per-target verdict — preserved,
  verified-compensated, approved-gap, failed, or unverified — with links to its
  evidence.
- **Run result**: The machine-readable record of a run: suites selected, targets
  attempted, per-check states (passed, failed, approved-gap, skipped, blocked),
  pin set, and evidence paths.
- **Approved gap entry**: A reviewed, identified capability loss for a target,
  with its disposition and any compensating control plus the check that
  demonstrates that control operating.
- **Mutation case**: A planted defect with the validator and failure reason
  expected in advance, used to prove the suite detects breakage.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The fast offline suite completes in under 3 minutes on the reference
  runner named in the suite's pins, with no network access and no harness
  credentials, and runs on every change. The budget is enforced in continuous
  integration, where the machine is known, and advisory elsewhere.
- **SC-002**: 100% of the capabilities in the versioned inventory appear in the
  report with exactly one recorded outcome per target; a capability with no
  recorded outcome fails the run.
- **SC-003**: 100% of planted mutation cases are detected, and each is attributed
  to the validator and reason declared for it in advance.
- **SC-004**: Repeat generation from identical frozen inputs produces byte-
  identical output in 100% of runs, and verification completes without modifying
  any file.
- **SC-005**: Generated artifacts produced in different workspaces are identical,
  containing zero machine-local values.
- **SC-006**: Every capability claimed as supported for a target is backed by
  either official schema evidence with a recorded version and digest, or an
  observed loader or behavioural probe; zero supported claims rest on format
  parsing alone.
- **SC-007**: Full mode exits nonzero in 100% of cases where a required target or
  mandatory layer is blocked or skipped, and no such run is described anywhere in
  its output as a pass.
- **SC-008**: A live skill run retains evidence of skill discovery, invocation and
  generator execution for 100% of live runs, together with the time, tokens and
  cost it consumed; where an operator has set an optional ceiling, 100% of runs
  that reach it are reported as failed rather than truncated silently.
- **SC-009**: Every approved gap in the report carries a specific reviewed
  identifier, and remains counted as a parity loss; zero gaps are absorbed into
  pass totals or matched by a pattern rule.
- **SC-010**: Zero runs modify the committed fixture, the oracle artifacts, or any
  path outside the workspace they created, verified after every suite.
- **SC-011**: Two suites started concurrently on the same machine both complete
  with correct results, with zero workspace, port or audit-log collisions.
- **SC-012**: 100% of retained logs and evidence are free of credentials when
  scanned by the redaction check.
- **SC-013**: The documented entry point covers itself: every flag, suite, exit
  code and result state it can produce is described in its own help output and in
  the suite's README, verified by a check that compares the two against the
  runner's actual option and exit-code table.
- **SC-014**: An upstream harness or documentation change with no repository
  change leaves gating results unchanged, surfacing only in the compatibility job.
- **SC-015**: 100% of conformance outcomes record the observed harness version,
  and zero outcomes produced against an unpinned version are counted as verified
  or reported as gate evidence.

## Assumptions

Defaults chosen where the brief left a detail open. Items marked *(to settle in
clarification)* are decisions the brief explicitly defers; the requirements above
stand regardless of how they are settled.

- Committed fixtures live under `tests/e2e/fixtures/complete-claude/` with
  variants alongside, as stated in the brief. The existing `tests/smoke.sh` is
  kept as-is and called by the new entry point's offline layer; it also remains
  directly runnable, so its own small throwaway fixture stays valid alongside the
  larger committed one.
- Codex and opencode are the required targets in full mode; an unavailable
  required target is blocked, never skipped silently. Devin is deferred by the
  clarification above: its adapters are validated offline, its live claims stay
  unverified, and it is added as a required target by a later change. Both
  required harnesses run locally on this machine, so no container or remote
  network arrangement is needed for them.
- Live, credentialed and paid runs are opt-in and never part of the default local
  or offline CI path. They run unbounded by default per the clarification above,
  with consumption measured and reported. *(to settle in clarification: which
  credentials are available for automated live runs)*
- Gating runs pin the Claude Code, Codex and opencode versions in use at
  implementation time — the versions present on the development machine today are
  Claude Code 2.1.263, Codex 0.153.4 and opencode 1.18.29 — recorded in each
  harness specification alongside its generation date. A separate compatibility
  job tracks latest versions, and a local run against a newer auto-updated harness
  is advisory rather than a gate result.
- The set of acceptable capability gaps starts from the dispositions Loom already
  records for permissions and hooks on targets that cannot express them, plus the
  untranslated markdown assets (skills, agents, rules, context placement). Each
  entry must be individually reviewed and identified before it can be treated as
  approved. *(to settle in clarification: the final approved-gap list)*
- The intent manifest and expectation sets are stored outside the temporary
  workspace and are read-only to any process that performs generation or
  specification refresh; enforcement is by filesystem isolation.
- The test system runs on Linux and macOS with the tools Loom already requires,
  plus a structured-format parser and schema validator; no network access is
  needed for the offline layer.
- Local fixture MCP services are simple deterministic processes started and
  stopped by the suite on unique ports; no public MCP endpoint and no real secret
  is used.
- Model-driven behavioural scenarios use a fixed trial count with thresholds set
  before execution; the counts are chosen during planning and are bounded by the
  scenario definition rather than by a cost ceiling.
- Expanding what Loom translates (skills, agents, rules) is out of scope here;
  those capabilities are inventoried and dispositioned as approved gaps whose
  entries name the target's native equivalent. The translator change that wires
  them in is specified separately as feature `002-link-context-assets`; when it
  lands, those inventory entries move from approved gap to preserved without any
  change to the oracle's structure.

## Dependencies

- Loom's installer, generator and emitters in this repository, exercised as the
  system under test from the working checkout including uncommitted changes.
- Real Claude Code, plus the Codex and opencode harnesses, for the live and
  conformance layers; their documented validation or startup interfaces. Devin is
  not a dependency of this feature; its adapters are exercised offline only.
- Official configuration schemas for the target harnesses where they exist, with
  recorded source, version, retrieval date and digest.
- Credentials for live layers, supplied out of band and injected per scenario;
  model spend is unbounded by default and is the operator's responsibility.
- The Loom constitution, which governs the honesty, isolation and evidence rules
  this specification encodes.
