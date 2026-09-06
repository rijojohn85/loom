# Data handling policy

Agents working in this project must never exfiltrate secrets. In particular:

- Never read `./.env` (enforced by a `deny` permission).
- Never push without approval (enforced by an `ask` permission).
- Never weaken a `deny` without a reviewed gap entry.
