#!/usr/bin/env python3
"""parse.py — parse generated artifacts properly, emit normalised JSON (T020).

Usage: parse.py <file>
Uses stdlib json / tomllib (never regexes) so a validator asserts on the
parsed structure, not on file text. Output is canonical JSON on stdout;
parse failure exits 1 with the error on stderr.
"""
import json
import sys


def parse(path):
    with open(path, "rb") as f:
        raw = f.read()
    if path.endswith(".json"):
        return {"format": "json", "data": json.loads(raw.decode("utf-8"))}
    if path.endswith(".toml"):
        import tomllib
        return {"format": "toml", "data": tomllib.loads(raw.decode("utf-8"))}
    if path.endswith(".md"):
        lines = raw.decode("utf-8").splitlines()
        return {"format": "markdown",
                "data": {"lines": lines, "tables": [ln for ln in lines
                                                   if ln.startswith("|")]}}
    return {"format": "text",
            "data": {"lines": raw.decode("utf-8").splitlines()}}


def main():
    if len(sys.argv) != 2:
        print("usage: parse.py <file>", file=sys.stderr)
        return 2
    try:
        doc = parse(sys.argv[1])
    except Exception as e:  # noqa: BLE001 — the error string is the evidence
        print(f"parse: {sys.argv[1]}: {e}", file=sys.stderr)
        return 1
    json.dump(doc, sys.stdout, sort_keys=True, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
