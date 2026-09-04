---
name: loom
description: Refresh the harness spec packs and regenerate AI-harness adapter
  configs with loom. Use when a harness (Codex, Devin, opencode, Claude Code)
  changed its agent config schema, when a spec pack is stale (lint warns),
  when an adapter needs a new capability, or when someone says "refresh
  loom", "update harness specs", or "regenerate the adapters".
---
# Loom — Phase A: refresh harness specs

Loom is two things (see the `loom.sh` header and the spec packs' README):

- **Phase A — refresh (you, this skill):** judgment — read docs, update a
  dated spec pack, change an emitter if the schema changed.
- **Phase B — emit (`loom.sh`):** deterministic — you never edit an
  adapter by hand. You edit the emitter, then re-run loom.

Find the paths first: `loom.config.json` (next to `loom.sh`, or wherever
the repo's lint target passes `--config`) names the canonical files, the
spec-pack directory, and the gaps ledger. Everything below refers to those.

## Process

1. **Identify what changed.** Source: the user's report, a stale spec pack
   (lint warning), or an upstream release note. If nothing changed and the
   pack is stale, re-verify the pack's claims and refresh its `generated:`
   date only if they still hold.
2. **Fetch the current docs** in this order: a docs MCP server if the repo
   has one (for example `context7`), then the official web docs (spec
   packs carry the URLs), then — only if the docs are ambiguous — a live
   probe in the affected harness, logged where the repo keeps conformance
   evidence.
3. **Update the spec pack** (`<spec_packs>/<harness>.md`): bump
   `generated:` to today, revise the schema table, keep every claim tied to
   a source URL or a probe reference. Note what the harness does *not*
   support — that list drives the gaps ledger.
4. **Decide: emitter change or not.** The pack records reality; the emitter
   encodes it. If the schema changed, update `lib/emit-<harness>.sh` (and
   `loom.config.json` for transport overrides) **in the same PR** — the
   pack is the evidence for the emitter diff.
5. **Regenerate and verify:**
   - `loom.sh` (apply)
   - `loom.sh --check` (must be clean)
   - the repo's lint target (drift gate, staleness warning, shellcheck)
   - re-run the affected harness's conformance probes if the adapter
     content changed beyond the generated header.
6. **Never touch adapter files by hand.** If `--check` fails, the answer is
   a regenerated emit or an emitter change — never a manual adapter edit.
   The only legitimate adapter diff is one produced by loom.

## Adding a harness

Drop `lib/emit-<name>.sh` defining `emit_<name> IR OUT` next to the other
emitters, write its spec pack, and loom picks it up with no core changes.
Read `lib/emit-devin.sh` for the fullest example (transport overrides,
permissions, hooks, gap rows) and the README's "Writing an emitter"
section for the IR shape.

## Acceptance for a refresh PR

- Spec pack diff: dated, sourced, honest about gaps
- Emitter diff (if any): justified by the pack diff
- `--check` clean, lint green, affected probes pass
