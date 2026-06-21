# DocMate Repair Handoff

Use this template before making documentation repairs. Keep it concise and evidence-based.

```text
Repair handoff
Original question: <user question>
Update mode: ask | auto
User confirmation: confirmed | not required by auto mode | pending
Decision: confirmed docs gap
Confidence: high | medium | low

Docs gap:
- <missing, outdated, contradictory, or vague documentation claim>

Docs evidence:
- <file path/section/line, or none found>

Code evidence:
- <file path, symbol, command, or repository>

Target docs repository:
- <repo name and path from docmate.catalog.json>

Affected docs:
- <candidate documentation files>

Expected minimal change:
- <smallest doc-only change that fixes the verified gap>

Out of scope:
- Code changes
- Unrelated documentation rewrites
- Formatting-only churn outside affected docs

Blockers:
- <missing auth, ambiguous remote, ambiguous target docs, or none>
```
