
Build an end-to-end test system for Loom, which installs a Claude Code skill
and deterministically translates canonical Claude Code project configuration
into Codex, Devin, and opencode adapters. Extend the existing tests/smoke.sh
coverage while retaining its fast, offline execution.

The primary user journey is:
1. Copy a committed, realistic Claude Code fixture into a fresh
   /tmp/loom-test-<timestamp> directory, with a collision-safe suffix if needed.
2. Initialize that directory as an independent Git repository, install Loom
   from the current working checkout using install.sh in copy mode, and invoke
   the installed /loom skill through real Claude Code.
3. Validate every generated artifact deterministically against independently
   defined expectations, versioned schemas, and actual target harness loaders.
4. Execute behavior scenarios to determine whether the intended configuration
   semantics survive translation, including negative and security scenarios.
5. Produce an evidence-backed report that distinguishes correctness, documented
   limitations, regressions, and unavailable validation.

### Fixture and independent oracle

- Store the fixture under tests/e2e/fixtures/complete-claude/. Include CLAUDE.md,
  AGENTS.md with explicit relationships, multiple skills with resources and
  executable helpers, multiple agents, scoped rules, policy documents, MCP
  allowlists, .mcp.json, .claude/settings.json, multiple hook events and matchers,
  and allow/deny/ask permissions. Use valid, documented configuration for a
  pinned Claude Code version. Include all referenced scripts and resources.
- Define "complete" through a versioned capability inventory, not an implicit
  promise to support every possible Claude Code feature. Cover HTTP and stdio
  MCPs, transport overrides, hook ordering, paths with spaces, escaping, empty
  configuration, and unsupported constructs through a base fixture plus variants.
  Treat currently rejected inputs (such as URL-less MCPs with the allowlist)
  as explicit negative cases rather than making the baseline impossible to run.
- Provide deterministic local MCP services and harmless hooks with observable
  audit logs. Avoid dependencies on public MCP uptime or real secrets. Dynamic
  endpoints must be recorded; repeatability comparisons must use identical
  resolved input, or documented normalization of designated ephemeral fields.
- Keep an independently authored intent manifest outside the agent-writable
  test repository. Give each source capability an ID, source location, intended
  behavior, per-harness expectation, positive/negative scenarios, and required
  evidence. Never derive this oracle from Loom's outputs or GAPS.md.
- Current Loom emitters chiefly handle MCPs, permissions, and hooks. Do not
  presume they translate skills, agents, rules, or all context semantics.
  Inventory these too: require native/shared support with evidence, an approved
  limitation, or a failure for silent loss. Keep translator feature expansion
  separate from the test implementation unless explicitly needed and specified.

### Isolation and installation

- Preserve dotfiles and executable bits when copying. Do not link back to the
  source checkout or mutate the committed fixture. Record source revision plus
  a digest of the installed working-tree files, including uncommitted changes.
- Isolate harness user configuration, caches, trust state, and environment using
  supported mechanisms. Inject only required credentials; never copy an entire
  developer home directory. Ensure the test really loads project configuration.
- Install the skill and tools with the repository installer. Verify their
  contents and locations; exercise reinstall preservation and custom paths.
- Use unique workspaces and ports for concurrent runs. Bound process lifetimes,
  terminate child processes, and preserve failed workspaces and useful logs.
  Provide explicit keep/cleanup controls and safe cleanup confined to owned paths.

### Real skill execution and reproducibility

- Invoking loom.sh alone is not skill E2E coverage. Record evidence that Claude
  Code discovered and invoked the installed skill, followed its workflow, and
  ran the installed generator. Capture structured events/transcripts, exit
  status, changed files, tool/model versions, and time/token/cost limits.
- Cover a no-change verification scenario and a controlled stale/schema-change
  scenario that exercises spec refresh and justified emitter changes. Supply
  versioned documentation evidence for reproducible scenarios; keep a separate
  live-docs scenario for upstream compatibility monitoring.
- The skill can change installed emitters and spec packs. Record those diffs
  and freeze the post-skill tool/input snapshot before repeat-generation checks.
  Prevent it from editing validators, expected results, or the intent manifest.
  Preserve canonical source configuration unless a scenario explicitly permits
  an independently specified source change.
- Separate fast offline deterministic checks, live Claude skill execution,
  actual harness conformance, and intent probes into selectable suites. Provide
  a full mode that requires all layers. Offline-only success must not be reported
  as full E2E success. Pin dependencies/schemas for gating and offer a separate
  latest-version compatibility job. Model execution itself is not deterministic.

### Deterministic artifact validation

- Parse JSON and TOML properly. Validate against official version-matched schemas
  where available; record source URL, version, retrieval date, and digest. Where
  no official schema exists, label local structural checks honestly and require
  native loader evidence for harness conformance. Reject unsupported fields.
- Check all artifacts, including adapter files, refreshed spec packs, GAPS.md,
  the generated manifest, references, and any unexpected files. Use an independent
  expected inventory so a missing manifest entry cannot hide a missing output.
- Run apply twice and compare generated bytes with identical frozen inputs;
  run --check, which must pass without modifying files. Check that separate
  workspaces do not leak absolute temporary paths into portable output.
- Deliberately edit/delete generated output and confirm --check fails. Cover
  orphan detection, single-harness generation, invalid source input, unapproved
  MCP names/endpoints, and failures that must not partially overwrite valid output.
- Validate that every unrepresentable capability has a precise ledger entry
  and a reviewed disposition. A prose compensating control is not evidence that
  the control actually operates.
- Include mutation tests: weaken a deny, drop a hook, change an MCP endpoint,
  omit an expected artifact, or corrupt a schema field. The relevant validator
  must fail for the intended reason.

### Actual harness conformance

- Test Claude Code as the source baseline and Codex, Devin, and opencode as
  targets. Discover and document their supported validation/startup interfaces;
  do not invent CLI flags or substitute a JSON parser for a harness loader.
- Verify the effective loaded configuration, not just a zero exit code. Use
  harmless canary settings or observable probes to detect ignored project files,
  unknown fields, trust gating, and user-level overrides.
- Exercise MCP initialization, tool discovery, and permitted calls against the
  local fixture services. Ensure container/remote harnesses can reach the fixture
  through an explicit test arrangement; do not assume their localhost is ours.
- If a harness requires a remote service, credentials, or unavailable tooling,
  report BLOCKED/SKIPPED with the reason and missing evidence. Full mode must
  return nonzero when any required harness is untested; never call this a pass.

### Intent and behavioral validation

- Test observable effects: a permitted docs call succeeds; a forbidden action
  produces no forbidden side effect; protected-file edits are blocked; an
  approval-required action cannot silently execute; a matching hook executes in
  the right order and a nonmatching hook does not; rules/context/skills/agents
  influence their designated task when claimed to be supported.
- First establish that scenarios express the intended behavior in Claude Code,
  then evaluate target behavior against the independent manifest. Define outcomes
  before execution. Do not equate matching syntax with matching semantics.
- Drive deterministic tool/hook probes directly where supported. For model-driven
  scenarios, use bounded repeated trials and predefined thresholds, preserve all
  attempts, and distinguish model task failure from config loading/enforcement
  failure. A dangerous side effect fails immediately; retries cannot erase it.
- An LLM intent reviewer may supplement deterministic evidence using a structured
  rubric and cited trace/artifact references. Its opinion cannot override a failed
  schema check, missing probe, forbidden side effect, or unsupported capability.
- Report capability outcomes as preserved, verified-compensated, approved-gap,
  failed, or unverified. An approved gap remains a loss of parity and must remain
  visible in totals. Require exact reviewed gap IDs; broad expected-failure rules
  must not hide new regressions.

### Delivery and acceptance

- Provide one documented local entry point with suite selection, a full mode,
  harness selection, timeouts, retention controls, and clear prerequisite checks.
  Add CI separation for offline gates and credentialed/live runs.
- Emit machine-readable results and a concise human report mapping capability
  IDs to assertions, harness/schema/model versions, evidence paths, gaps, failures,
  and skips. Redact credentials from retained logs.
- Document installation, reproducible execution, upstream pin refresh, fixture
  extension, and gap review. Keep existing smoke coverage passing.
- Acceptance requires a demonstrated full run for available required harnesses,
  explicit blocked status for unavailable ones, and proof that deliberate
  artifact and behavioral mutations are caught. Never weaken expectations merely
  to make existing emitters green.
- During clarification, settle remote Devin access, credentials and model budget,
  gating harness versions, and which known capability gaps are acceptable.
  Default to all three targets required in full mode, local fixtures, and explicit
  opt-in for paid live runs. These are implementation prerequisites, not reasons
  to omit their requirements from the specification.
