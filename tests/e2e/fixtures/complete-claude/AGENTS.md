# AGENTS.md — agent instructions for the demo project

## Relationships

- `CLAUDE.md` imports this file: project context flows from here into every
  agent session.
- `docs/api.md` is the public API surface; agents must keep it in sync with
  `src/` when they change behaviour.
- `agent/policies/allowed-mcp-servers.md` is the MCP endpoint policy; only
  servers listed there may be called.
- `agent/policies/data-handling.md` states what agents must never exfiltrate.

## Rules

- Run `make lint` before proposing a patch.
- Never remove a `deny` permission without a reviewed gap entry.
- Hooks in `hooks/` run on every file write; keep them fast and deterministic.
