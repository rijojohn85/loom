# LLM intent reviewer rubric

The reviewer reads one scenario's traces and artifacts and judges whether
the recorded outcome is supported. The review is SUPPLEMENTARY: it can add
context but can never override a deterministic failure, a missing probe, an
unmet schema check, or an observed forbidden side effect.

## What to cite (every claim needs both)

1. A trace reference: the exact stream-json line (session id + tool use id)
   showing the behaviour.
2. An artifact reference: the evidence path (digest manifest, audit log,
   adapter file) corroborating it.

## Verdicts

- `supported`: every cited check has both references and they agree.
- `contested`: a reference is missing or two references disagree — say which.
- `refused`: the trace is insufficient to judge — say what is missing.

## Output (JSON, stdout)

{"scenario": "<id>", "harness": "<h>", "verdict": "supported|contested|refused", "citations": [{"claim": "...", "trace": "...", "artifact": "..."}], "note": "..."}

Record the reviewer model and consumption alongside every other live
scenario. A contested or refused review does not change any check state.
