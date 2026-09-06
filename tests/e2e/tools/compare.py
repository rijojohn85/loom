#!/usr/bin/env python3
"""compare.py — byte comparison with declared ephemeral normalisation (T023).

Usage: compare.py <fileA> <fileB> [--resolved-input <resolved-input.json>]
Byte-identical files exit 0. With --resolved-input, every value listed in
`ephemeral_fields` (a {name: value} map) is replaced by <ephemeral:name> in
both files before comparing; the names normalised are printed as
`NORMALIZED: a,b`. Anything else that differs exits 1 with a unified diff.
"""
import difflib
import json
import sys


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print("usage: compare.py <fileA> <fileB> "
              "[--resolved-input <resolved-input.json>]", file=sys.stderr)
        return 2
    file_a, file_b = args[0], args[1]
    resolved = None
    if "--resolved-input" in args:
        idx = args.index("--resolved-input")
        with open(args[idx + 1], encoding="utf-8") as f:
            resolved = json.load(f)
    with open(file_a, encoding="utf-8") as f:
        a = f.read()
    with open(file_b, encoding="utf-8") as f:
        b = f.read()
    if a == b:
        print("IDENTICAL")
        return 0
    normalised = []
    if resolved:
        fields = resolved.get("ephemeral_fields", {})
        for name, value in fields.items():
            if value and (value in a or value in b):
                normalised.append(name)
                a = a.replace(value, f"<ephemeral:{name}>")
                b = b.replace(value, f"<ephemeral:{name}>")
        if a == b:
            print(f"IDENTICAL after normalising: {','.join(normalised)}")
            print(f"NORMALIZED: {','.join(normalised)}")
            return 0
    diff = "".join(difflib.unified_diff(
        a.splitlines(keepends=True), b.splitlines(keepends=True),
        fromfile=file_a, tofile=file_b))
    sys.stdout.write(diff or "files differ (non-text or encoding)\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
