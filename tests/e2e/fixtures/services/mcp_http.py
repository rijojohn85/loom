#!/usr/bin/env python3
"""Local HTTP MCP service for the e2e fixture (T027, research D3).

Stdlib only. Streamable-HTTP-ish JSON-RPC: `initialize`, `tools/list`,
`tools/call` with a constant two-tool surface (docs.get, docs.list)
returning constant content. Appends one line per call to an audit log.

Usage: mcp_http.py <port> <audit-log>
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1])
AUDIT = sys.argv[2]

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


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, payload):
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        try:
            req = json.loads(self.rfile.read(length).decode())
        except Exception:
            self._send({"jsonrpc": "2.0", "id": None,
                        "error": {"code": -32700, "message": "parse error"}})
            return
        method = req.get("method", "")
        rid = req.get("id")
        if method == "initialize":
            audit("http initialize")
            self._send({"jsonrpc": "2.0", "id": rid,
                        "result": {"protocolVersion": "2024-11-05",
                                   "capabilities": {"tools": {}},
                                   "serverInfo": {"name": "fixture-docs",
                                                  "version": "1.0.0"}}})
        elif method == "tools/list":
            audit("http tools/list")
            self._send({"jsonrpc": "2.0", "id": rid,
                        "result": {"tools": TOOLS}})
        elif method == "tools/call":
            name = (req.get("params") or {}).get("name", "")
            audit(f"http tools/call {name}")
            if name == "docs.get":
                result = {"content": [{"type": "text",
                                       "text": "constant fixture page"}]}
            elif name == "docs.list":
                result = {"content": [{"type": "text",
                                       "text": "api,readme"}]}
            else:
                self._send({"jsonrpc": "2.0", "id": rid,
                            "error": {"code": -32602,
                                      "message": f"unknown tool {name}"}})
                return
            self._send({"jsonrpc": "2.0", "id": rid, "result": result})
        else:
            audit(f"http unknown {method}")
            self._send({"jsonrpc": "2.0", "id": rid,
                        "error": {"code": -32601,
                                  "message": f"unknown method {method}"}})


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
