---
harness: codex
harness_version: 0.153.4
generated: 2026-09-06
status: seeded from live conformance probes + upstream docs; re-verify on next Phase A run
---

# Spec pack: Codex

## Files loom emits

| Kind | Path | Schema |
|------|------|--------|
| context | `AGENTS.md` | read natively, no import needed |
| MCP | `.codex/config.toml` | `[mcp_servers.<name>]` → `url`, `default_tools_approval_mode = "auto"` |
| permissions | same file | approval mode only; no per-tool glob allowlist |
| hooks | **not supported** | compensating control: `.githooks/pre-commit` + `.github/workflows/ci.yml` (recorded in GAPS.md) |
| skills | not file-configurable | prompts dir only |

## Verified by live probe (2026-09-03)

- AGENTS.md read natively in non-interactive `codex exec`
- `[mcp_servers.*]` with `default_tools_approval_mode = "auto"` allows
  docs-server tool calls without per-call confirmation
- No hook mechanism exists in the config schema

## Source URLs

- https://developers.openai.com/codex/config-advanced (project config, trust)
- https://developers.openai.com/codex/mcp

## Emitter notes

- Comment header allowed (TOML has comments)
- Every IR hook event is a GAPS row
- Every permissions entry (allow, deny, ask, defaultMode) is a GAPS row —
  the approval mode is the only permission surface
- Server names are written as quoted, TOML-escaped table keys
  (`[mcp_servers."name"]`) so odd characters cannot corrupt the file
