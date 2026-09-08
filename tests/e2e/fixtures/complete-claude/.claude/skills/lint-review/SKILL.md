---
name: lint-review
description: Review a patch for lint and policy compliance before proposing it
---

# lint-review skill

Review the pending diff against `resources/checklist.md`, then summarise with
`scripts/summarize.sh`. Never weaken a `deny` permission to make lint pass.
