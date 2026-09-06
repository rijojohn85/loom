# Feature Specification: Carry Markdown Context Assets Into Target Harnesses

**Feature Branch**: `002-link-context-assets`

**Created**: 2026-09-06

**Status**: Draft — deferred (drafted out of band during clarification of `001-e2e-test-system`; re-run `/speckit-clarify` on this spec before planning)

**Input**: User direction during clarification of feature 001: "skills, agents and rules should be symlinked since they're md files, is that not done? if not, create a new spec for it, I'll take it up later"

## Context

Loom's emitters translate MCP servers, permissions and hooks. They do not carry
any of the canonical markdown assets — the context file, `.claude/skills/*/SKILL.md`
and their resources, `.claude/agents/*.md`, scoped rules, and policy documents.
Verified in the current implementation: `lib/emit-codex.sh` writes only
`.codex/config.toml`, `lib/emit-opencode.sh` writes only `opencode.json`,
`lib/emit-devin.sh` writes only `.devin/*.json`, and `loom.sh` merely records the
canonical context path — nothing is linked, copied, or transformed.

The committed spec packs already record the shape of the opportunity: all three
targets read `AGENTS.md` natively; opencode has `agent/` and `command/`
directories described as "not wired from Claude today"; Codex and Devin list
skills as "not file-configurable". So part of this is a straightforward link and
part is a genuine capability gap that must stay recorded.

Because these are plain markdown files, the preferred mechanism is a relative
symlink rather than a copy: one file on disk, no second copy to drift, and the
drift gate keeps watching it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One context file, read by every harness (Priority: P1)

A maintainer keeps the canonical context in one place and expects Codex, Devin and
opencode to read the same words, without a second copy to maintain.

**Why this priority**: Context is the asset every target supports natively, so it
is the highest value for the least mechanism, and it establishes the link-and-
verify machinery the later stories reuse.

**Independent Test**: Generate into a fixture repository whose canonical context
lives somewhere other than the repository root, then confirm each target harness
reads the canonical text, and that the drift gate notices if the placement is
removed or altered.

**Acceptance Scenarios**:

1. **Given** a canonical context file, **When** generation runs, **Then** each
   target that reads a context file natively finds the canonical content at the
   location that target documents, with no duplicated copy of the text in the
   repository.
2. **Given** the canonical context file is edited, **When** the target harness
   next reads it, **Then** it sees the new content with no regeneration required.
3. **Given** the generated placement is deleted or replaced with different
   content, **When** the verification mode runs, **Then** it fails and names the
   affected path.
4. **Given** a repository where the canonical context already sits exactly where
   a target expects it, **When** generation runs, **Then** no placement is created
   and no file is overwritten.

---

### User Story 2 - Agents and commands available in the targets that support them (Priority: P2)

A maintainer who has written agent definitions for Claude Code expects the targets
with an equivalent concept to offer the same agents, rather than silently having
none.

**Why this priority**: This is where a real, documented native location exists in
at least one target, so it converts a recorded gap into preserved parity.

**Independent Test**: Point generation at a fixture containing several agent
definitions, then confirm the target harness lists and can select those agents,
and that a target without the concept records a gap instead.

**Acceptance Scenarios**:

1. **Given** canonical agent definitions and a target with a documented native
   agent location, **When** generation runs, **Then** each definition is available
   to that target at its documented location and the harness lists it.
2. **Given** a canonical definition whose required metadata differs from the
   target's required metadata, **When** generation runs, **Then** the mismatch is
   either resolved by a generated, deterministic transformation or recorded as a
   gap — it MUST NOT produce a file the target rejects.
3. **Given** a target with no native agent concept, **When** generation runs,
   **Then** a gap entry is written naming the capability, the target, and the
   compensating control.
4. **Given** a user-authored file already present at a destination, **When**
   generation runs, **Then** it is not overwritten; the conflict is reported.

---

### User Story 3 - Skills and scoped rules dispositioned, never dropped silently (Priority: P3)

A maintainer needs each remaining markdown asset — skills with their resources and
executable helpers, scoped rules, policy documents — to end up either available in
a target or visibly recorded as a gap.

**Why this priority**: Coverage completeness. It closes the parity ledger for
markdown assets, but the targets' support here is thinnest, so it delivers the
least behaviour change.

**Independent Test**: Run against a fixture containing skills with resources and
helper scripts plus scoped rules, and confirm every asset appears in the ledger
with a disposition and, where support exists, at the documented location with its
resources intact.

**Acceptance Scenarios**:

1. **Given** a skill with resource files and an executable helper, **When** it is
   carried into a target that supports skills, **Then** the resources resolve and
   the helper remains executable.
2. **Given** a target that supports skills only at user scope rather than project
   scope, **When** generation runs, **Then** this is recorded as a gap with its
   evidence, not as support.
3. **Given** scoped rules that apply to a subset of paths, **When** they are
   carried into a target with no scoping concept, **Then** the loss of scoping is
   recorded as a gap rather than silently widening the rule's reach.
4. **Given** any canonical markdown asset, **When** generation completes, **Then**
   it appears exactly once in the ledger as preserved, compensated, or a recorded
   gap.

---

### Edge Cases

- The canonical asset and the target's expected location are the same path: no
  placement is created, and nothing is overwritten.
- A destination already holds a user-authored file: generation reports the
  conflict and leaves the file alone.
- A previously generated placement is no longer produced: it is detected as an
  orphan by the existing manifest-based check.
- The working tree is on a filesystem or platform where symlinks are unavailable
  or not preserved by the version control checkout.
- A target harness resolves symlinks differently, refuses to follow them, or
  applies its own path scoping to linked content.
- Asset names contain spaces or characters requiring escaping in a target's
  configuration format.
- A skill's helper script loses its executable bit through the placement
  mechanism.
- A canonical asset is deleted: its placement is removed on the next generation
  and does not linger.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Generation MUST make canonical markdown assets — context file,
  skills and their resources, agents, scoped rules, and policy documents —
  available to each target harness at the location that target documents, wherever
  documented support exists.
- **FR-002**: Placement MUST default to a relative symbolic link to the canonical
  file, so a single file on disk serves every harness and editing the canonical
  file needs no regeneration.
- **FR-003**: Where a link cannot be used — the platform or checkout does not
  preserve symlinks, or evidence shows the target does not follow them — the
  system MUST fall back to a deterministic generated copy, MUST record which
  mechanism was used, and MUST keep the copy under the drift gate.
- **FR-004**: Generation MUST NOT overwrite or delete a user-authored file at a
  destination; a conflict MUST be reported and MUST fail the run.
- **FR-005**: Every placement MUST be recorded in the generated manifest so the
  verification mode detects a deleted, altered, or orphaned placement.
- **FR-006**: Verification MUST fail when a placement is missing, points at the
  wrong canonical file, or has been replaced by unmanaged content.
- **FR-007**: Where a target's format requires metadata that differs from the
  canonical asset's metadata, the system MUST either apply a deterministic
  transformation that the target accepts, or record a gap; it MUST NOT emit a file
  the target rejects.
- **FR-008**: Every canonical markdown asset MUST end in exactly one recorded
  state per target — preserved, compensated, or recorded gap — and silent
  omission MUST fail the run.
- **FR-009**: A claim that a target supports an asset type MUST cite dated,
  versioned documentation or a probe against the harness, recorded in that
  target's spec pack in the same change as the emitter behaviour.
- **FR-010**: Scoping, ordering, or precedence semantics that a target cannot
  express MUST be recorded as a gap rather than approximated silently.
- **FR-011**: Executable bits and relative resource references within a carried
  skill MUST survive placement.
- **FR-012**: Generation MUST remain deterministic, offline, model-free, and
  byte-identical for identical inputs, and MUST NOT embed absolute paths.
- **FR-013**: Removing a canonical asset MUST remove its placements on the next
  generation, leaving no orphan.
- **FR-014**: Adding this behaviour MUST NOT change the existing MCP, permission
  or hook translation, and existing generated artifacts MUST remain byte-identical
  where their inputs are unchanged.
- **FR-015**: The feature MUST be exercised by the end-to-end test system
  specified in `001-e2e-test-system`; the corresponding inventory entries move
  from approved gap to preserved when this feature lands.

### Key Entities

- **Canonical asset**: A markdown file (with optional sibling resources and
  helper scripts) authored once for Claude Code — context, skill, agent, rule, or
  policy document.
- **Placement**: The link (or, as a fallback, generated copy) that makes a
  canonical asset visible to one target at that target's documented location.
- **Placement mechanism**: Which of link or copy was used, recorded per placement.
- **Asset disposition**: The per-asset, per-target outcome — preserved,
  compensated, or recorded gap — carried into the existing gap ledger.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A maintainer maintains exactly one copy of each markdown asset;
  zero duplicated bodies of the same text exist in the repository after
  generation.
- **SC-002**: 100% of canonical markdown assets appear in the ledger with exactly
  one disposition per target.
- **SC-003**: Editing a canonical asset changes what every supporting harness
  reads with zero regeneration steps.
- **SC-004**: 100% of deleted, altered, or orphaned placements are caught by the
  verification mode.
- **SC-005**: Zero user-authored files are overwritten or deleted across all
  generation runs.
- **SC-006**: Every "supported" claim for an asset type carries dated
  documentation or probe evidence; zero rest on inference.
- **SC-007**: Repeat generation from identical inputs is byte-identical, and
  previously generated MCP, permission and hook artifacts are unchanged.

## Assumptions

- The repository is on a platform and version control checkout that preserves
  symbolic links and executable bits (Linux and macOS); Windows checkouts are
  handled by the copy fallback in FR-003.
- All three targets read a context file natively, per the committed spec packs;
  opencode has native agent and command directories; Codex and Devin do not offer
  project-scoped skills. These claims are re-verified with dated evidence during
  implementation, not taken from this spec.
- Placements are committed to the repository alongside other generated artifacts,
  so a fresh clone works without running generation first.
- Target harnesses follow symbolic links when reading configuration; where
  evidence shows otherwise, that target uses the copy fallback.

## Open Decisions

To settle with `/speckit-clarify` before planning:

- Whether metadata mismatches (for example, differing frontmatter requirements
  between a Claude skill and a target's agent format) should be resolved by a
  generated transformed file — which forfeits the single-file property for that
  asset — or recorded as a gap and left uncarried.
- Whether placements are committed to the repository or generated locally and
  ignored by version control.
- Whether carrying agents and skills into a target that lacks Claude Code's
  permission and hook enforcement is acceptable, given that a carried agent may
  describe behaviour the target cannot constrain.
- Which asset types are in scope for the first release, given that Codex and
  Devin offer no project-scoped skill location today.

## Dependencies

- The committed harness spec packs and their evidence discipline.
- The existing manifest and drift-gate mechanism, extended to cover placements.
- The end-to-end test system in `001-e2e-test-system` for verification of the
  resulting behaviour in the target harnesses.
