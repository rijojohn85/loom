#!/usr/bin/env python3
"""redact.py — credential redaction gate (T095, FR-026, SC-012).

Usage: redact.py <file> [<file> ...]
Scans each file for credential material: the values of known credential
environment variables plus generic secret patterns. A file that matches is
REFUSED (exit 1, offending pattern class on stdout) — the run fails rather
than retaining the file. Clean files exit 0.
"""
import os
import re
import sys

GENERIC_PATTERNS = [
    r"AKIA[0-9A-Z]{16}",                       # AWS access key id
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----",     # private key material
    r"xox[bap]-" ,                              # slack tokens
    r"ghp_[A-Za-z0-9]{20,}",                   # github tokens
    r"sk-ant-[A-Za-z0-9_-]{10,}",              # anthropic keys
    r"sk-[A-Za-z0-9]{20,}",                    # openai-style keys
]

CREDENTIAL_ENV_HINTS = ("KEY", "TOKEN", "SECRET", "PASSWORD", "CREDENTIALS")


def main(files):
    literals = set()
    for name, value in os.environ.items():
        if not value or len(value) < 8:
            continue
        if name == "PATH" or name.startswith(("E2E_", "LOOM_")):
            continue
        if any(h in name for h in CREDENTIAL_ENV_HINTS):
            literals.add(value)
    failed = False
    for path in files:
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                content = f.read()
        except OSError as e:
            print(f"REFUSED {path}: unreadable ({e})")
            failed = True
            continue
        hits = [f"env:{n}" for n, v in os.environ.items()
                if v and len(v) >= 8 and v in content
                and any(h in n for h in CREDENTIAL_ENV_HINTS)]
        for pat in GENERIC_PATTERNS:
            if re.search(pat, content):
                hits.append(f"pattern:{pat}")
        if hits:
            print(f"REFUSED {path}: credential material ({', '.join(hits)})")
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: redact.py <file> [<file> ...]", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
