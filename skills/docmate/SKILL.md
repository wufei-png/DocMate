---
name: docmate
description: "Use for project documentation QA: answer from docs, verify stale or implementation-sensitive claims against code, report documentation gaps, and optionally repair confirmed gaps via pull request or merge request."
---

# DocMate

## Required Catalog Step

Read `references/docmate.catalog.json` before selecting a repository. Do not guess from the current directory when the user has not named a repository.

Choose the repository by comparing the user's request with these catalog fields when present:

- `name`
- `description`
- `aliases`
- `path`

If one repository is clearly best, continue. If two or more repositories are plausible and the answer would materially differ, ask the user to choose.

## Evidence Priority

When documentation and code conflict, treat code as the source of truth for runtime behavior and report the documentation as stale unless generated docs prove otherwise.

## Answer Workflow

1. Work from the selected repository `path`.
2. Discover documentation in that repository before answering. Prefer obvious documentation entry points such as README files, `docs/`, documentation site content, runbooks, and links referenced by those files.
3. Keep evidence explicit and concise. Cite the document and code evidence used; cite external sources only when requested or necessary. Omit unused categories unless their absence matters. Label inference that combines sources.
4. Classify the request and follow the answer decision table.

## Answer Decision Table

Use this decision table before answering:

| Decision | When to use it | Required action |
| --- | --- | --- |
| `docs-only ok` | The documentation directly answers the question and the answer does not depend on runtime behavior, defaults, generated values, metrics, field names, or implementation details. | Answer directly from documentation with document evidence, then stop. |
| `must verify code` | The question involves implementation behavior, defaults, configuration precedence, API fields, metrics labels, supported values, or a documentation claim that could be stale. | Verify from code before answering. If the related code repository is ambiguous, ask only after checking the current working directory, git remotes, documentation links, and nearby workspace repositories. |
| `insufficient evidence` | Documentation and discovered code do not provide enough evidence, or the related code repository remains ambiguous after local discovery. | State what is unknown, cite what was checked, ask only for the missing repository or decision, then stop. |
| `confirmed docs gap` | Documentation is missing, outdated, contradicted by code, or too vague, and code/document evidence identifies the affected docs. | In `auto`, when the gap is high confidence, target docs are clear, and the fix is a small doc-only change, repair may run before the final answer. Otherwise answer with evidence and a user-facing gap report first, then discuss repair. |

## Gap report

Report a documentation gap to the user when documentation is missing, outdated, contradicted by code, or too vague for the user's question. In `ask` mode, this report is also the confirmation context before any edit.

Use this shape:

```text
Gap report
Gap Confidence: high | medium | low
Original question: <user question>
Doc evidence: <paths or none found>
Code evidence: <paths or commands checked>
Target docs repo: <selected repo name and path>
Affected docs: <candidate doc files>
Suggested fix: <smallest doc-only change>
Blockers: <missing auth, ambiguous target docs, ambiguous remote, or none>
```

Only proceed to documentation repair when the gap is confirmed and the affected documentation target is clear.

## Update Modes

Read the global `defaults.update.mode` value from the catalog. Repository-level update modes are not supported.

- `defaults.update.mode = ask`: Ask the user before any edit. Proceed only after explicit confirmation.
- `defaults.update.mode = auto`: Proceed without asking only for a high-confidence confirmed gap with clear doc and code evidence, clear target docs, and a small doc-only fix.
- `defaults.update.mode = off`: Report the gap and stop. Do not edit files.

When updates are enabled, infer the hosting provider and push remote from the selected repository's git remotes and the available native tools. If the provider or remote is ambiguous, stop and report the blocker.

## Documentation Repair Workflow

Documentation repair is part of this skill workflow. It does not require a subagent.

1. Resolve the base branch from `baseBranchCandidates`. Do not use hardcoded branch names.
2. Use the gap report as repair context. In `ask` mode, do not ask again if the user already confirmed repair during the answer workflow; otherwise show the gap report and wait for explicit confirmation before editing.
3. Create a temporary git worktree from the selected base branch. Do not require the user's main worktree to be clean, but do not modify it. Use git worktree from the repository object database only.
4. If the target docs no longer match the confirmed gap or upstream already fixed it, stop with `already_fixed_upstream`.
5. Create a descriptive branch name for the documentation fix.
6. Make the smallest doc-only change that fixes the verified gap. If the gap affects docs generated by GitLab CI or scripts, edit the source file that feeds generation rather than generated output, so the fix is not overwritten.
7. Review `git status --short` and `git diff` before committing. If code or unrelated files changed, stop and report the blocker.
8. Commit, push, and open a pull request or merge request with the native tools inferred from git remotes:
   - GitHub remotes use `gh pr create`.
   - GitLab remotes use `glab mr create`.

## Safety Rules

- Never modify code files during documentation repair.
- Do not require the user's main worktree to be clean, but never modify it.
- Never use destructive git commands to clean or reset a user's worktree.
- Never stash or discard user changes.
- Never create a pull request or merge request if the target docs no longer match the confirmed gap or blockers remain.
- If authentication, remote, branch, or tool state is unclear, stop and report the blocker.
