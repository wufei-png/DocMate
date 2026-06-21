# DocMate Golden Evals

These cases define expected DocMate behavior for documentation Q&A and docs-gap detection. They are intentionally repository-agnostic so they can be adapted to real project fixtures later.

Use them to track:

- Wrong-answer rate: answers that ignore available evidence or overstate certainty.
- Missed-gap rate: confirmed doc/code gaps reported as normal answers.
- False-repair rate: cases where DocMate would open a PR/MR without a confirmed high-confidence gap.

Each JSONL entry contains:

- `id`: stable case identifier.
- `question`: representative user request.
- `fixture`: abstract evidence available to the agent.
- `expectedDecision`: one of `docs-only ok`, `must verify code`, `insufficient evidence`, or `confirmed docs gap`.
- `expectedEvidence`: required evidence categories.
- `expectedRepair`: whether documentation repair is allowed.
- `notes`: what the case is meant to catch.

Validate the cases:

```bash
python3 evals/run_forward_tests.py
```

Generate blind prompts for a fresh agent:

```bash
python3 evals/run_forward_tests.py --write-prompts /tmp/docmate-prompts
```

Grade JSONL responses from that run:

```bash
python3 evals/run_forward_tests.py --responses /tmp/docmate-responses.jsonl
```
