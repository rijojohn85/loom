# Allowed MCP servers

Fixture policy for the Loom e2e suite. Endpoints are templated with the
allocated fixture URLs when the workspace is materialised.

## Approved servers

| Server | Endpoint | Access |
|--------|----------|--------|
| docs-a | `{{MCP_HTTP_URL_A}}` | read-only |
| docs-b | `{{MCP_HTTP_URL_B}}` | read-only |
| docs-local | `stdio://docs-local` | read-only |

## Notes

Read-only docs servers. Tool calls are pre-approved per this table.
