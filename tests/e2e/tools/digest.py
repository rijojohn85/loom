#!/usr/bin/env python3
"""digest.py — stable tree digests for workspace, fixture and oracle (T022).

Usage: digest.py <path> [<path> ...]
Prints one SHA-256 hex digest over sorted relative paths plus file contents,
so identical trees hash identically on every machine. Symlinks are hashed by
target string (a symlink escaping the tree is reported on stderr).
"""
import hashlib
import os
import sys


def tree_digest(root):
    h = hashlib.sha256()
    root = os.path.abspath(root)
    if os.path.isfile(root) and not os.path.islink(root):
        with open(root, "rb") as f:
            h.update(b"F\x00" + os.path.basename(root).encode() + b"\x00")
            h.update(f.read())
        return h.hexdigest()
    entries = []
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames.sort()
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root)
            entries.append((rel, full))
    for rel, full in entries:
        if os.path.islink(full):
            target = os.readlink(full)
            h.update(b"L\x00" + rel.encode() + b"\x00" + target.encode() + b"\x00")
            if os.path.isabs(target) or os.path.normpath(
                os.path.join(os.path.dirname(full), target)
            ).startswith(".."):
                print(f"digest: symlink escapes tree: {rel} -> {target}",
                      file=sys.stderr)
        elif os.path.isfile(full):
            h.update(b"F\x00" + rel.encode() + b"\x00")
            with open(full, "rb") as f:
                for chunk in iter(lambda: f.read(65536), b""):
                    h.update(chunk)
            h.update(b"\x00")
    return h.hexdigest()


def main(paths):
    digests = []
    for p in paths:
        if not os.path.exists(p):
            print(f"digest: no such path: {p}", file=sys.stderr)
            return 2
        d = tree_digest(p)
        digests.append(d)
        if len(paths) > 1:
            print(f"{d}  {p}")
    if len(paths) == 1:
        print(digests[0])
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: digest.py <path> [<path> ...]", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
