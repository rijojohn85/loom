#!/usr/bin/env python3
"""Local stdio MCP service for the e2e fixture (T028, research D3).

Same constant two-tool surface as mcp_http.py (docs.get, docs.list),
JSON-RPC over stdin/stdout, one audit-log line per call.

Usage: mcp_stdio.py <audit-log>
"""
import json
import sys

AUDIT = sys.argv[1]

TOOLS = [
    {"name": "docs.get",
     "description": "Return one constant docs page",
     "inputSchema": {"type": "object",
                     "properties": {"page": {"type": "string"}}}},
    {"name": "docs.list",
     "description": "List the constant docs pages",
     "inputSchema": {"type": "object", "properties": {}}},
]


def audit(line):
    with open(AUDIT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception:
            sys.stdout.write(json.dumps(
                {"jsonrpc": "2.0", "id": None,
                 "error": {"code": -32700,
                           "message": "parse error"}}) + "\n")
            sys.stdout.flush()
            continue
        method = req.get("method", "")
        rid = req.get("id")
        if method == "initialize":
            audit("stdio initialize")
            resp = {"result": {"protocolVersion": "2024-11-05",
                               "capabilities": {"tools": {}},
                               "serverInfo": {"name": "fixture-docs",
                                              "version": "1.0.0"}}}
        elif method == "tools/list":
            audit("stdio tools/list")
            resp = {"result": {"tools": TOOLS}}
        elif method == "tools/call":
            name = (req.get("params") or {}).get("name", "")
            audit(f"stdio tools/call {name}")
            if name == "docs.get":
                resp = {"result": {"content": [
                    {"type": "text", "text": "constant fixture page"}]}}
            elif name == "docs.list":
                resp = {"result": {"content": [
                    {"type": "text", "text": "api,readme"}]}}
            else:
                resp = {"error": {"code": -32602,
                                  "message": f"unknown tool {name}"}}
        else:
            audit(f"stdio unknown {method}")
            resp = {"error": {"code": -32601,
                              "message": f"unknown method {method}"}}
        resp.update({"jsonrpc": "2.0", "id": rid})
        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
