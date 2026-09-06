#!/usr/bin/env python3
"""schema_validate.py — official-schema validation (T021, FR-035).

Usage: schema_validate.py <schema.json> <instance.json>
Exit 0: instance valid. Exit 1: invalid (errors on stdout as JSON).
Exit 3: BLOCKED — the pinned jsonschema venv is absent. The caller must
record `blocked`, never skipped and never passed.
"""
import json
import os
import sys


def main():
    if len(sys.argv) != 3:
        print("usage: schema_validate.py <schema.json> <instance.json>",
              file=sys.stderr)
        return 2
    try:
        import jsonschema
    except ImportError:
        print(json.dumps({"status": "blocked",
                          "reason": "bootstrapped venv absent — "
                                    "run tests/e2e/run.sh --bootstrap"}))
        return 3
    with open(sys.argv[1], encoding="utf-8") as f:
        schema = json.load(f)
    with open(sys.argv[2], encoding="utf-8") as f:
        instance = json.load(f)
    validator = jsonschema.Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(instance), key=lambda e: list(e.path))
    if not errors:
        print(json.dumps({"status": "valid",
                          "schema": os.path.basename(sys.argv[1])}))
        return 0
    print(json.dumps({"status": "invalid",
                      "errors": [f"{'/'.join(map(str, e.path))}: {e.message}"
                                 for e in errors]}))
    return 1


if __name__ == "__main__":
    sys.exit(main())
