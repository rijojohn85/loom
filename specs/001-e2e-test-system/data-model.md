# Phase 1 Data Model: End-to-End Test System for Loom

All entities are files on disk. Oracle entities are authored by hand and are
read-only to everything under test; run entities are produced by the runner.

## Oracle entities (hand-authored, never generated)

### CapabilityRecord — `tests/e2e/oracle/capabilities.json`

The versioned inventory that defines what "complete" means (FR-010, FR-011).

| Field | Type | Notes |
|---|---|---|
| `id` | string | Stable identifier, e.g. `mcp.http.docs-a`, `perm.deny.rm-rf`, `hook.pre.write-order` |
| `kind` | enum | `mcp` · `permission` · `hook` · `context` · `skill` · `agent` · `rule` · `policy` |
| `source` | object | `{ file, pointer }` — where in the canonical fixture it lives |
| `intent` | string | What the capability is meant to do, in one sentence |
| `expectations` | map | harness → `ExpectedDisposition` |
| `scenarios` | array | Scenario ids that exercise it, positive and negative |
| `evidence_required` | array | One or more of `official-schema`, `harness-loader-probe`, `behaviour-probe`, `local-structural` |

`ExpectedDisposition`: `{ state: preserved \| compensated \| approved-gap \| unverified, gap_id?, native_equivalent?: { exists: bool, evidence?: string } }`.

**Vocabulary**: the oracle states what is *expected* and uses `compensated`; a run
reports what was *observed* and uses `verified-compensated`, which is the same
capability plus proof that its compensating control actually operated. An expected
`compensated` that reaches the end of a run without that proof is reported
`approved-gap`, never `verified-compensated`. The other four state names are
identical in both vocabularies.
`native_equivalent` is mandatory when `state` is `approved-gap` (FR-012a).

Inventory-level fields: `inventory_version` (semver, appears in every report) and
`claude_code_version` (the pinned source-baseline version the fixture targets).

### ExpectedArtifact — `tests/e2e/oracle/expected-artifacts.json`

The independent artifact inventory (FR-016), deliberately not derived from Loom's
generated manifest.

| Field | Type | Notes |
|---|---|---|
| `path` | string | Workspace-relative path |
| `producer` | string | Which harness emitter or core step must produce it |
| `format` | enum | `json` · `toml` · `markdown` · `text` |
| `required` | bool | `false` marks artifacts that exist only in certain variants |
| `assertions` | array | Ids in `expectations/<harness>/` that must hold |
| `variants` | array | Fixture variants this applies to; empty means the base |

### ApprovedGap — `tests/e2e/oracle/approved-gaps.json`

| Field | Type | Notes |
|---|---|---|
| `gap_id` | string | Exact, reviewed identifier — pattern rules are forbidden (FR-055) |
| `capability_id` | string | Must exist in the inventory |
| `harness` | string | The target that cannot represent it |
| `disposition` | string | Why this loss is accepted, and by whom |
| `reviewed_on` | date | |
| `native_equivalent` | object | `{ exists, evidence }` — a backlog marker when true |
| `compensating_control` | object | `{ description, verified_by }`; `verified_by` names the check that demonstrates the control operating, or is `null`, in which case the state is `approved-gap`, never `verified-compensated` (FR-041) |

### Scenario — `tests/e2e/oracle/scenarios/<id>.json`

| Field | Type | Notes |
|---|---|---|
| `id` | string | |
| `capability_ids` | array | What it exercises |
| `kind` | enum | `deterministic-probe` · `model-driven` |
| `baseline` | object | Expected observable outcome in Claude Code, defined before execution (FR-049) |
| `targets` | map | harness → expected observable outcome |
| `forbidden_side_effects` | array | Observable effects that fail the run immediately, retries notwithstanding (FR-051) |
| `trials` | object | Model-driven only: `{ count, threshold }`, fixed in advance |

### MutationCase — `tests/e2e/oracle/mutations.json`

| Field | Type | Notes |
|---|---|---|
| `id` | string | |
| `operation` | enum | `weaken-deny` · `drop-hook` · `change-mcp-endpoint` · `omit-artifact` · `corrupt-schema-field` · `hand-edit-artifact` · `delete-artifact` · `orphan-artifact` · `weaken-expectation` |
| `target` | object | `{ path?, pointer?, scenario_id? }` |
| `expected_failing_validator` | string | Validator id that must fail |
| `expected_reason_pattern` | string | Regex the recorded failure reason must match (FR-042) |

## Pinned inputs

### PinSet — `tests/e2e/pins/*.json`

| Field | Type | Notes |
|---|---|---|
| `harnesses` | map | name → `{ version, pinned_on, interfaces: [...] }` |
| `dependencies` | map | tool → version (`jq`, `python3`, `jsonschema`, `bash`) |
| `schemas` | array | `{ harness, url, version, retrieved_on, sha256, local_path }` |
| `fixture_revision` | string | Digest of the committed fixture tree |
| `source_revision` | string | git revision of the checkout under test |
| `worktree_digest` | string | SHA-256 over the installed working-tree files, uncommitted changes included (FR-020) |

## Run entities (generated per run, under `tests/e2e/results/<run-id>/`)

### RunResult — `results.json`

Conforms to `contracts/results.schema.json`. Top level: `run_id`, `started_at`,
`finished_at`, `mode` (`offline` · `selected` · `full`), `suites_selected`,
`harnesses_selected`, `pins`, `checks[]`, `capabilities[]`, `summary`, `verdict`.

`verdict` is computed, never asserted: `full-e2e-pass` requires mode `full`, every
mandatory check `passed`, and zero `blocked`/`skipped` mandatory checks. Any other
combination yields `offline-pass`, `partial`, or `failed` (FR-004, FR-053).

### CheckResult — `checks[]`

| Field | Type | Notes |
|---|---|---|
| `id` | string | e.g. `offline.idempotence`, `conformance.codex.strict-config` |
| `suite` | enum | `offline` · `mutation` · `live` · `conformance` · `intent` |
| `mandatory` | bool | |
| `state` | enum | `passed` · `failed` · `approved-gap` · `skipped` · `blocked` |
| `reason` | string | Required for every non-passed state; the string mutation cases match against |
| `claim_kind` | enum | `official-schema` · `harness-loader-probe` · `behaviour-probe` · `local-structural` · `none` |
| `harness` | string? | |
| `harness_version_observed` | string? | |
| `pinned` | bool | `false` marks an advisory local run against an unpinned harness version (FR-057b) |
| `attempts` | array | Every attempt, in order; a later success never removes an earlier failure (FR-051) |
| `evidence` | array | Run-relative paths |
| `duration_ms` | integer | |

### CapabilityOutcome — `capabilities[]`

`{ capability_id, harness, state: preserved \| verified-compensated \| approved-gap \| failed \| unverified, gap_id?, evidence[], checks[] }`.
Exactly one record per (capability, harness) pair; a missing pair fails the run
(SC-002).

### Consumption — embedded in live/intent checks

`{ elapsed_ms, input_tokens, output_tokens, cost_usd, model, ceiling: null \| {...} }`.
Recorded always; `ceiling` is null unless the operator opted into one (FR-028a).

### EvidenceBundle — `evidence/<check-id>/`

Transcripts (`stream-json.jsonl`), harness probe outputs, hook audit logs,
generated-artifact copies, digest manifests, and diffs. Written through the
redaction pass; the run refuses to retain a file matching a credential pattern.

### WorkspaceRecord — `workspace.json`

`{ path, created_at, ports: {service: port}, kept: bool, git_revision, isolation_env: {HOME, XDG_*, CODEX_HOME, CLAUDE_CONFIG_DIR}, oracle_digest_before, oracle_digest_after, trust_seeded: {harness: {seeded: bool, mechanism, path, approved_mcp_servers[]}} }`.

`trust_seeded` is mandatory evidence, not bookkeeping: seeding trust is a
deliberate departure from a default-untrusted workspace, and a reader must be able
to see which gate was opened, how, and for which servers. The unseeded negative
check (`conformance.<harness>.untrusted-canary`) records `seeded: false`.

### ResolvedInput — `resolved-input.json`

The frozen inputs a generation ran against: fixture variant, templated MCP URLs
and allocated ports, loom config, installed tool digests. Repeat-generation uses
this file, so byte comparison is meaningful; the cross-workspace comparison
normalises only fields listed in `ephemeral_fields` (D3).

## Relationships

```text
CapabilityRecord 1..n ── expectations ──> ExpectedDisposition ──> ApprovedGap (when approved-gap)
CapabilityRecord 1..n ── scenarios ─────> Scenario ──> CheckResult (per harness, per attempt)
ExpectedArtifact 1..n ── assertions ────> CheckResult
MutationCase 1..1 ─────────────────────> CheckResult (must be `failed` with matching reason)
RunResult 1..n ── checks ──────────────> CheckResult
RunResult 1..n ── capabilities ────────> CapabilityOutcome ──> CapabilityRecord
```

## State rules

1. Every `CapabilityRecord` × selected harness produces exactly one
   `CapabilityOutcome`; absence is a run failure, not a silent omission.
2. `verified-compensated` requires an `ApprovedGap.compensating_control.verified_by`
   naming a check that itself `passed`.
3. `approved-gap` requires a matching `gap_id` in `approved-gaps.json`.
4. `unverified` is the only legal state for a deferred target (Devin) and never
   contributes to a pass total.
5. A `CheckResult` with `pinned: false` may not set `claim_kind` to
   `official-schema` or `harness-loader-probe` for gating purposes; it is advisory.
6. Any `forbidden_side_effects` observation sets the owning check to `failed`
   permanently, regardless of later attempts.
