---
name: docmate
description: "Documentation QA assistant that answers from project docs and code, detects documentation gaps, and can repair docs by opening a pull request or merge request."
---

# DocMate

Use this skill for documentation QA, project documentation lookup, doc-vs-code verification, documentation gaps, and documentation repair requests.

## Required Catalog Step

Read `references/docmate.catalog.json` before selecting a repository. Do not guess from the current directory when the user has not named a repository.

Choose the repository by comparing the user's request with each catalog entry:

- `name`
- `description`
- `aliases`
- `path`

If one repository is clearly best, continue. If two or more repositories are plausible and the answer would materially differ, ask the user to choose.

## Answer Workflow

1. Work from the selected repository `path`.
2. Discover documentation in that repository before answering. Prefer obvious documentation entry points such as README files, `docs/`, documentation site content, runbooks, and links referenced by those files.
3. Verify implementation details, runtime behavior, defaults, field names, configuration, and unsupported or missing documentation claims from code evidence discovered in the selected repository or from related repositories found during the task.
4. If code evidence is needed but the related code repository is ambiguous, ask the user only after checking the current working directory, git remotes, links in the documentation, and nearby workspace repositories.
5. Answer the user's original question before discussing documentation repair.
6. Keep evidence explicit:
   - Document evidence: cite the files or sections found in the selected repository.
   - Code evidence: cite the files, symbols, or commands checked in the selected repository or related repositories.
   - Inference: label conclusions that combine multiple sources.

## Answer Decision Table

Use this decision table before answering:

| Decision | When to use it | Required action |
| --- | --- | --- |
| `docs-only ok` | The documentation directly answers the question and the answer does not depend on runtime behavior, defaults, generated values, metrics, field names, or implementation details. | Answer from docs and cite document evidence. |
| `must verify code` | The question involves implementation behavior, defaults, configuration precedence, API fields, metrics labels, supported values, or a documentation claim that could be stale. | Check code evidence before answering. |
| `insufficient evidence` | Documentation and discovered code do not provide enough evidence, or the related code repository remains ambiguous after local discovery. | Say what is unknown, cite what was checked, and ask only for the missing repository or decision. |
| `confirmed docs gap` | Documentation is missing, outdated, contradicted by code, or too vague, and code/document evidence identifies the affected docs. | Answer the user, produce a gap report, then follow `defaults.update.mode`. |

## Evidence Chain

When an answer depends on documentation, code, or external material, include an evidence chain after the direct answer.

Use this shape:

```text
Evidence chain
Decision: docs-only ok | must verify code | insufficient evidence | confirmed docs gap
Docs evidence:
- Fact [1]: <finding>
  Source: <file path and section/line, or none found>
Code evidence:
- Fact [2]: <finding>
  Source: <file path, symbol, command, or repository>
External evidence:
- Fact [3]: <finding>
  Source: <URL or external system, only when used>
Inference:
- <how the evidence supports the answer, including conflicts or uncertainty>
```

Omit evidence categories that were not used, except when the absence of evidence is material to the answer or gap report. If sources conflict, identify the conflict and prefer code evidence for current implementation behavior unless the user explicitly asks for documented behavior only.

## Gap report

Create a compact gap report when documentation is missing, outdated, contradicted by code, or too vague for the user's question.

Use this shape:

```text
Gap report
Status: confirmed_gap | likely_gap | no_gap
Confidence: high | medium | low
Doc evidence: <paths or none found>
Code evidence: <paths or commands checked>
Affected docs: <candidate doc files>
Suggested fix: <smallest doc-only change>
```

Only proceed to documentation repair when the gap is confirmed and the affected documentation target is clear.
For repair handoff details, use `references/repair-handoff.template.md`.

## Update Modes

Read the global `defaults.update.mode` value from the catalog. Repository-level update modes are not supported.

- `defaults.update.mode = ask`: Ask the user before any edit. Proceed only after explicit confirmation.
- `defaults.update.mode = auto`: Proceed without asking only for a high-confidence confirmed gap with clear doc and code evidence.
- `defaults.update.mode = off`: Report the gap and stop. Do not edit files.

When updates are enabled, infer the hosting provider and push remote from the selected repository's git remotes and the available native tools. If the provider or remote is ambiguous, stop and report the blocker.

## Documentation Repair Workflow

Documentation repair is part of this skill workflow. It does not require a subagent.

1. Resolve the base branch from `baseBranchCandidates`. Do not use hardcoded branch names.
2. Prepare a repair handoff using `references/repair-handoff.template.md`. In `ask` mode, show the handoff and wait for explicit user confirmation before editing.
3. Create a temporary git worktree from the selected base branch. Do not edit the user's main worktree.
4. Re-check the gap in the fresh worktree.
5. If upstream already fixed it, stop with `already_fixed_upstream`.
6. Create a descriptive branch name for the documentation fix.
7. Make the smallest doc-only change that fixes the verified gap.
8. Review `git status --short` and `git diff` before committing. If code or unrelated files changed, stop and report the blocker.
9. Commit, push, and open a pull request or merge request with the native tools inferred from git remotes:
   - GitHub remotes use `gh pr create`.
   - GitLab remotes use `glab mr create`.
10. Final response must include:
   - Status
   - Summary
   - Changed files
   - Base branch
   - Pull request or merge request link
   - Blockers, if any

## Safety Rules

- Never modify code files during documentation repair.
- Never use destructive git commands to clean or reset a user's worktree.
- Never stash or discard user changes.
- Never create a pull request or merge request without first re-checking the gap in the temporary worktree.
- If authentication, remote, branch, or tool state is unclear, stop and report the blocker.
