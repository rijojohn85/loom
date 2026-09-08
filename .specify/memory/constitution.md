<!--
SYNC IMPACT REPORT
==================
Version change: (unversioned template) → 1.0.0
Bump rationale: Initial ratification. The prior file was an unfilled scaffold with
no adopted principles, so this is the first governing version rather than an
amendment of an existing one.

Modified principles:
  - [PRINCIPLE_1_NAME] (placeholder) → I. Deterministic Generation
  - [PRINCIPLE_2_NAME] (placeholder) → II. No Silent Loss of Intent
  - [PRINCIPLE_3_NAME] (placeholder) → III. Evidence-Backed Harness Compatibility
  - [PRINCIPLE_4_NAME] (placeholder) → IV. Independent Validation (NON-NEGOTIABLE)
  - [PRINCIPLE_5_NAME] (placeholder) → V. Real End-to-End Coverage
  - (new) → VI. Observable Intent Checks
  - (new) → VII. Reproducibility and Isolation
  - (new) → VIII. Honest Test Outcomes (NON-NEGOTIABLE)
  - (new) → IX. Regression-Detecting Tests
  - (new) → X. Controlled Change and Maintainability

Added sections:
  - Operating Constraints (fills [SECTION_2_NAME]), including a standing
    Compliance Status subsection recording known shortcomings as open work
  - Development Workflow and Review Gates (fills [SECTION_3_NAME])
  - Governance, expanded with an explicit exception process and amendment/
    versioning rules

Removed sections: none (all template slots filled)

Follow-up TODOs: none. All placeholder tokens resolved.

Templates and downstream artifacts requiring review for alignment:
  - .specify/templates/plan-template.md — Constitution Check gate should
    reference Principles I–X
  - .specify/templates/spec-template.md — no change identified
  - .specify/templates/tasks-template.md — no change identified
  - .specify/templates/checklist-template.md — no change identified
-->

# Loom Constitution

Loom treats Claude Code project configuration as the single source of truth and
generates configuration for other AI coding harnesses. Everything below governs
how that translation is built, validated, and changed. Where a rule says MUST,
a change that violates it is not mergeable without a recorded exception. Where a
rule says SHOULD, a deviation is permitted but MUST be justified in review.

This constitution defines the standard Loom is held to. It does not assert that
the current implementation already meets it; see **Compliance Status**.

## Core Principles

### I. Deterministic Generation

Generation MUST produce its outputs without a language model and without network
access. Given identical canonical inputs, identical configuration, and identical
tool versions, generation MUST produce byte-identical outputs on every run and on
every machine. Generated output MUST NOT embed machine-local state — absolute
workspace paths, timestamps, hostnames, user names, or environment-dependent
ordering — unless that value is derived solely from the pinned inputs.

Model-assisted work (refreshing harness specifications, judging whether an
emitter must change) is a separate phase from generation. That phase MAY use a
model, docs, and the network; it MUST NOT become a runtime dependency of
generation. Generation MUST remain runnable, and MUST be run, with the model
phase absent.

Rationale: a translator that a reviewer cannot re-derive is not a source of
truth — it is a second thing to trust. Determinism is what makes the drift gate
meaningful and what lets a diff be reviewed instead of re-litigated.

### II. No Silent Loss of Intent

Every capability expressed in the canonical configuration MUST end in exactly one
of three recorded states for each target harness: **preserved** (natively carried
into the generated artifact), **compensated** (carried by a named control whose
operation is demonstrated, not merely asserted), or **recorded gap** (an explicit,
reviewed entry in the capability-gap ledger).

The following are forbidden and MUST fail the build rather than degrade quietly:

- Weakening a restriction — narrowing a deny, broadening an allow, downgrading an
  approval requirement to an automatic action, or dropping a matcher's specificity.
- Omitting a restriction, hook, or server from an artifact without a ledger entry.
- Claiming support for a capability without evidence that the target harness
  actually honors it.

A documented gap is a real loss of parity, not parity. Gaps MUST remain visible in
any summary or total that reports coverage; a gap MUST NOT be netted out, folded
into a pass count, or described as equivalent behavior. A prose compensating
control is a claim; it becomes a compensation only when its operation is
demonstrated by a check.

Rationale: silent loss is Loom's defining failure mode. A drifted or quietly
weakened adapter is a policy hole that nobody is looking at, which is strictly
worse than a hole everyone can see.

### III. Evidence-Backed Harness Compatibility

Every claim about what a target harness supports MUST cite evidence of one of
these kinds, and the kind MUST be recorded alongside the claim:

- Versioned official documentation, with source URL, harness version, and
  retrieval date.
- An official schema, with source URL, version, retrieval date, and content digest.
- A conformance probe against the actual harness, with a retained trace.

Successfully parsing a generated file MUST NOT be reported as harness support. A
JSON or TOML parser is not a harness loader, and a zero exit status is not proof
that a harness loaded, trusted, and enforced project configuration. Where no
official schema exists, local structural checks MUST be labeled as local
structural checks and MUST NOT be presented as schema validation.

Claims MUST be classified as **verified** (probe or schema evidence),
**assumed** (documentation only, or inference), or **unvalidated** (no evidence
available). Assumptions MUST state what would falsify them. Harness
specifications MUST carry a generation date and MUST be refreshed, or re-verified
and re-dated, when they exceed the project's staleness threshold.

Rationale: the whole value of a generated adapter is that the target actually
behaves as the canonical configuration intended. Untested belief about a third
party's schema is the least reliable input Loom has.

### IV. Independent Validation (NON-NEGOTIABLE)

Expected behavior MUST be defined independently of Loom's outputs. The intent
manifest, validators, schemas, and approved gap definitions are the oracle; they
MUST NOT be derived from generated artifacts, from the gap ledger, or from
whatever the current emitters happen to produce.

An agent or process that performs generation or specification refresh MUST NOT
modify test expectations, validators, schemas, approved gap definitions, or the
intent manifest, and MUST NOT modify the canonical source configuration except
where a scenario explicitly and independently specifies that change. These
artifacts MUST be writable only outside the workspace the generating agent
controls, enforced by isolation rather than by instruction alone.

Changes to expectations MUST be a separate, human-reviewed change carrying an
explicit justification: what behavior changed, why the old expectation was wrong,
and what evidence supports the new one. "The implementation does not do this"
is never sufficient justification for relaxing an expectation.

Rationale: a test suite the implementation is allowed to edit measures nothing.
This is the principle that keeps every other principle enforceable.

### V. Real End-to-End Coverage

An end-to-end claim MUST exercise the complete user journey: copy a realistic
canonical fixture into an isolated temporary repository; install Loom from the
working checkout under test, including uncommitted changes; invoke the installed
skill through real Claude Code; validate the generated artifacts; and exercise
the resulting behavior in the target harnesses.

Running the generator directly MUST NOT be reported as skill end-to-end coverage.
A skill-level claim MUST retain evidence that the harness discovered the installed
skill, invoked it, followed its workflow, and ran the installed generator —
captured as structured events or transcripts, exit status, changed files, and the
tool and model versions in use.

The suite MUST separate its layers — fast offline deterministic checks, live
skill execution, harness conformance, and behavioral intent probes — so each can
be selected and reported on its own, and MUST provide a full mode that requires
every mandatory layer. Success in one layer MUST NOT be reported as success in
another.

Rationale: the failures that matter to a user live in the seams — installation,
discovery, invocation, loading — and none of those seams is exercised by calling
the generator directly.

### VI. Observable Intent Checks

Validation MUST test observable effects, not matching syntax. Matching structure
between a canonical file and a generated file is not evidence of matching
semantics. Verification MUST cover, for each capability claimed as supported:
that a permitted action succeeds; that a forbidden action produces no forbidden
side effect; that an approval-required action cannot execute without approval;
that a matching hook executes, in the intended order, and a non-matching hook does
not; that MCP initialization, tool discovery, and permitted calls behave as
intended; and that context, rule, skill, and agent behavior claimed as supported
demonstrably influences the task it is claimed to influence.

Scenarios MUST first establish that they express the intended behavior in Claude
Code — the source baseline — before target behavior is judged against the intent
manifest. Expected outcomes MUST be defined before execution.

Model-based assessment MAY supplement deterministic evidence using a structured
rubric with cited traces. It MUST NOT override a deterministic failure, a missing
probe, an unmet schema check, or an observed forbidden side effect. Deterministic
probes MUST be preferred wherever the harness supports them. Model-driven
scenarios MUST use bounded repeated trials against thresholds fixed in advance,
MUST preserve every attempt, and MUST distinguish a model task failure from a
configuration loading or enforcement failure.

Rationale: Loom exists to preserve what the configuration *does*. Only observed
effects measure that; everything else measures what a file looks like.

### VII. Reproducibility and Isolation

Gating checks MUST pin their inputs: dependency versions, harness versions,
schema versions and digests, fixture revisions, and the digest of the installed
working-tree files under test. Live upstream compatibility checking — latest
harness versions, current published docs — MUST run as a separate, clearly
labeled job and MUST NOT gate reproducible regression runs, because upstream can
change without any change in this repository.

Test execution MUST be isolated from developer state: an independent temporary
repository, isolated harness user configuration, caches, trust state, and
environment; unique workspaces and ports so concurrent runs cannot collide.
Committed fixtures MUST NOT be mutated, and the test workspace MUST NOT link back
to the source checkout. Only the credentials a scenario requires may be injected;
wholesale copying of a developer's home directory or credential store is
forbidden.

Failure evidence MUST be preserved — retained workspaces, logs, and traces —
under explicit retention controls, with credentials and secrets redacted.
Cleanup MUST be confined to paths the run created. Child processes MUST be
bounded and terminated.

Rationale: a result that cannot be reproduced cannot be acted on, and a test that
reads developer state produces passes that belong to one machine.

### VIII. Honest Test Outcomes (NON-NEGOTIABLE)

Results MUST distinguish, as separate states that are separately counted:
**passed**, **failed**, **approved gap**, **skipped** (deliberately not run), and
**blocked** (could not run — missing tooling, credentials, or an unreachable
service). Full end-to-end success requires every check designated mandatory to
have passed; full mode MUST exit nonzero when any required harness or layer is
blocked or skipped.

Missing tooling, absent credentials, or an unavailable harness MUST NEVER produce
a pass. Silently degrading to a weaker check, skipping a layer and reporting
success, or treating an unreachable target as "not applicable" are all forbidden.

Retries MUST preserve every attempt in the record. A retry MUST NOT overwrite or
erase a prior failure, and MUST NEVER clear a security-relevant failure or an
observed forbidden side effect — one occurrence of a forbidden side effect is a
failure regardless of how many subsequent attempts behave.

Expected-failure or known-gap allowances MUST reference exact, reviewed gap
identifiers. Broad or pattern-matched expected-failure rules that could absorb an
unrelated new regression are forbidden.

Rationale: a suite that reports green when it did not run is worse than no suite,
because it converts an unknown into a false assurance.

### IX. Regression-Detecting Tests

The suite MUST demonstrate that it catches breakage, not merely that it passes.
It MUST include positive checks (intended behavior present), negative checks
(invalid input rejected, forbidden action denied), drift checks (a hand-edited or
deleted generated artifact, and an orphaned artifact regeneration no longer
produces, both detected), idempotence checks (repeat generation from frozen
inputs is byte-identical, and verification passes without modifying files), and
mutation checks.

Mutation checks MUST deliberately break artifacts and behavior — weaken a deny,
drop a hook, alter an MCP endpoint, omit an expected artifact, corrupt a schema
field — and MUST confirm that the relevant validator fails **for the intended
reason**, not merely that something failed. A validator that cannot be shown to
fail on a planted defect MUST NOT be counted as coverage.

A fast offline suite MUST be retained and MUST stay fast enough to run on every
change, alongside bounded live harness and model-driven suites. Failures MUST NOT
leave partially overwritten valid output.

Rationale: an untested validator is an assumption wearing a test's clothing.

### X. Controlled Change and Maintainability

Generated adapters MUST NOT be edited by hand. The only legitimate change to a
generated artifact is one produced by regeneration after changing the canonical
source configuration, the project configuration, or an emitter. When the drift
gate fails, the resolution is a source or emitter change followed by
regeneration — never a manual edit to the artifact.

Adding a harness SHOULD require only a new emitter plus its dated specification,
with no change to the core translation. An emitter change that adds or alters a
compatibility claim MUST land in the same change as the specification evidence
that justifies it.

Installation MUST preserve existing user configuration and user-authored
specifications while refreshing the tool and skill. Changes that affect
compatibility — generated artifact shape, supported capabilities, gap
dispositions, pinned harness or schema versions — MUST be documented in the
change that makes them.

Implementation changes MUST stay scoped to what the task requires. New
abstraction, configuration surface, or indirection MUST be justified by a
concrete present requirement; anticipated future needs are not sufficient.

Rationale: Loom's premise is that one source of truth beats four hand-maintained
copies. A manual patch to a generated file re-creates precisely the drift Loom
exists to eliminate.

## Operating Constraints

**Scope of authority.** This constitution governs Loom's translation behavior,
its validation and test system, and changes to both. It applies to code,
emitters, harness specifications, fixtures, validators, and CI configuration in
this repository. It supersedes conflicting guidance in READMEs, skill
instructions, agent context files, and habit.

**Scope of the product.** Loom translates project-scoped configuration. It has no
authority over configuration a developer adds at user scope inside their own
harness, and MUST NOT claim to. Capabilities outside the current translation
surface MUST still be inventoried and dispositioned under Principle II rather
than left unmentioned.

**Terminology.** *Canonical configuration* is the Claude Code project
configuration that is the source of truth. An *emitter* turns the normalized
intermediate representation into one harness's artifacts. A *harness
specification* is the dated, sourced evidence for what an emitter hardcodes. The
*gap ledger* records capabilities a harness cannot represent. The *intent
manifest* is the independently authored oracle of expected behavior. The *drift
gate* is the check that regenerated output matches what is committed. Concrete
file names, directory layouts, command-line flags, and individual test cases are
deliberately absent from this document; they belong to feature specifications and
plans, which may change without amending this constitution.

**Compliance Status.** As of ratification, the implementation does not yet
satisfy this constitution. The following are recorded as open work, not as
accepted exceptions, and MUST be addressed through specified features rather than
by weakening the principles:

- No end-to-end coverage invokes the installed skill through real Claude Code;
  existing coverage exercises the generator directly (Principle V).
- No independently authored intent manifest exists, and no isolation prevents a
  generating agent from editing expectations (Principle IV).
- Harness compatibility rests on documentation-derived specifications without
  conformance probes or version-matched official schema validation; claims are not
  yet classified as verified, assumed, or unvalidated (Principle III).
- Compensating controls for recorded gaps are prose assertions whose operation is
  not demonstrated by any check (Principle II).
- No behavioral or intent probes verify permitted actions, denials, approval
  requirements, hook ordering, or MCP calls in target harnesses (Principle VI).
- No mutation checks demonstrate that validators fail on planted defects
  (Principle IX).
- Results reporting does not distinguish blocked from skipped from approved gap
  (Principle VIII).

**Update 2026-09-06 (feature `001-e2e-test-system`, `tests/e2e/`):** all seven
items above are closed by the layered test system — live skill execution (V),
hand-authored oracle with digest enforcement and read-only live phases (IV),
loader probes plus vendored official-schema validation with recorded claim
kinds (III), gap ledger with demonstrated-or-null compensating controls and
exact gap ids (II), behavioural intent scenarios with permanent
forbidden-side-effect failure (VI), a mutation registry proving every
validator fails for its declared reason (IX), and five-state honest outcomes
with a computed verdict (VIII). Residual notes (not violations):
translator limitations (stdio-url gate, matcher loss, untranslated
context/assets) stay inventoried as approved gaps, owned by feature
`002-link-context-assets`; Devin stays deferred (`unverified`, never gating);
model-driven probes report `blocked` without credentials or target auth, per
the live-and-credentialed-runs rule. The e2e suite itself is now the
enforcement mechanism for these principles; keep this list current as
shortcomings are found.

This list MUST be reviewed at every compliance review and updated as items are
closed or new shortcomings are found.

## Development Workflow and Review Gates

**Planning gate.** Every feature plan MUST include a Constitution Check that names
the principles the work touches and states how each is satisfied. Work that
cannot pass the check as designed MUST be redesigned or MUST carry a recorded
exception before implementation begins.

**Pre-merge gates.** A change MUST NOT merge unless all of the following hold:

1. The fast offline suite passes, including the drift gate and idempotence check.
2. Generated artifacts in the change are reproducible from the sources in the same
   change; no artifact carries a hand-authored diff.
3. Every capability the change touches has a preserved, compensated, or recorded
   gap disposition, and the gap ledger reflects it.
4. Any new or altered compatibility claim carries dated, sourced evidence in the
   corresponding harness specification, in the same change.
5. Any change to validators, expectations, schemas, approved gaps, or the intent
   manifest is separately identified and separately justified, and was not
   authored by the process whose output it validates.
6. Test outcomes are reported with pass, fail, gap, skipped, and blocked
   distinguished; no blocked or skipped mandatory check is reported as success.

**Review responsibilities.** A reviewer MUST verify claims against evidence rather
than against assertion: that cited sources exist and are dated, that probes ran,
that a compensating control is demonstrated rather than described. A reviewer MUST
reject a change that relaxes an expectation to accommodate implementation
behavior without independent justification.

**Live and credentialed runs.** Runs that require credentials, paid model usage,
or remote harness access MUST be opt-in and MUST be separated in CI from
reproducible offline gates. Their absence MUST surface as blocked, never as pass.

**Compliance review.** The Compliance Status list MUST be reviewed whenever a
release is cut or a target harness is added, whichever comes first, and the
result recorded in the change that performs the review.

## Governance

**Supremacy.** This constitution supersedes other development practices in this
repository. Where guidance conflicts, this document governs, and the conflicting
guidance MUST be corrected.

**Amendment procedure.** An amendment MUST be proposed as a change that contains:
the exact text added, removed, or altered; the rationale, including what problem
the current text fails to address; the impact on existing features, plans, and
templates; and a migration note for any work the amendment invalidates. An
amendment MUST be reviewed and approved by a project maintainer other than its
author where more than one maintainer is available. Amendments take effect on
merge and are not retroactive: work already merged under a prior version is not
in violation, but MUST be brought into compliance when next materially changed.

**Versioning policy.** This constitution is versioned MAJOR.MINOR.PATCH.

- MAJOR: a principle is removed, or redefined in a way that permits what it
  previously forbade, or governance rules change incompatibly.
- MINOR: a principle or section is added, or existing guidance is materially
  expanded or tightened.
- PATCH: clarification, wording, formatting, or typo correction that does not
  change what is required.

Every amendment MUST update the version, the Last Amended date, and the Sync
Impact Report at the top of this file.

**Exception process.** An exception is a time-bounded, recorded permission to
violate a specific rule. Exceptions to principles marked NON-NEGOTIABLE
(IV, VIII) MUST NOT be granted. For any other rule, an exception MUST record: the
exact principle and clause; the precise scope, narrowed to the smallest surface
that resolves the problem; the rationale, including what was tried and why
compliance is not currently possible; the evidence supporting that rationale; the
compensating measure that limits exposure while the exception stands; an expiry
date or the concrete condition that ends it; and the approver. An exception MUST
be approved by a maintainer who did not author the work it covers, where more
than one maintainer is available. Exceptions MUST be recorded in the affected
feature's plan and surfaced in review — an undocumented deviation is a violation,
not an exception. Expired exceptions MUST be renewed with fresh justification or
closed by bringing the work into compliance. An exception is never grounds for
amending a principle; amending to legalize existing behavior requires the full
amendment procedure and its own rationale.

**Non-compliance.** A merged violation MUST be recorded in the Compliance Status
list and scheduled for correction. Reporting a violation as compliant — a false
pass, an unrecorded gap, an undemonstrated compensating control described as
verified — is itself a violation of Principle VIII and MUST be corrected before
any dependent claim is published.

**Version**: 1.0.0 | **Ratified**: 2026-09-06 | **Last Amended**: 2026-09-06
