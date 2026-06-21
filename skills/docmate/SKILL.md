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

## Evidence Priority

When documentation and code conflict, treat code as the source of truth for runtime behavior and report the documentation as stale unless generated docs prove otherwise.

## Answer Workflow

1. Work from the selected repository `path`.
2. Discover documentation in that repository before answering. Prefer obvious documentation entry points such as README files, `docs/`, documentation site content, runbooks, and links referenced by those files.
3. Keep evidence explicit and concise. Cite the document, code, and external sources used; omit unused categories unless their absence matters. Label inference that combines sources.
4. Classify the request with the answer decision table.
5. If the decision is `docs-only ok`, answer directly from documentation with document evidence, then stop.
6. If the decision is `must verify code`, verify implementation details, runtime behavior, defaults, field names, configuration, and unsupported or missing documentation claims from code evidence. If the related code repository is ambiguous, ask the user only after checking the current working directory, git remotes, links in the documentation, and nearby workspace repositories.
7. If the decision is `insufficient evidence`, state what is unknown, cite what was checked, ask only for the missing repository or decision, then stop.
8. If the decision is `confirmed docs gap`, choose the response order from `defaults.update.mode`: in `auto`, when the gap is high confidence, the target docs are clear, and the fix is a small doc-only change, documentation repair may run before the final answer; otherwise answer the user's question with evidence and a user-facing gap report first, then discuss repair.

## Answer Decision Table

Use this decision table before answering:

| Decision | When to use it | Required action |
| --- | --- | --- |
| `docs-only ok` | The documentation directly answers the question and the answer does not depend on runtime behavior, defaults, generated values, metrics, field names, or implementation details. | Answer from docs and cite document evidence. |
| `must verify code` | The question involves implementation behavior, defaults, configuration precedence, API fields, metrics labels, supported values, or a documentation claim that could be stale. | Check code evidence before answering. |
| `insufficient evidence` | Documentation and discovered code do not provide enough evidence, or the related code repository remains ambiguous after local discovery. | Say what is unknown, cite what was checked, and ask only for the missing repository or decision. |
| `confirmed docs gap` | Documentation is missing, outdated, contradicted by code, or too vague, and code/document evidence identifies the affected docs. | Answer the user, produce a user-facing gap report, then follow `defaults.update.mode`. |

## Gap report

Report a documentation gap to the user when documentation is missing, outdated, contradicted by code, or too vague for the user's question. In `ask` mode, this report is also the confirmation context before any edit.

Use this shape:

```text
Gap report
Status: confirmed_gap | likely_gap | no_gap
Confidence: high | medium | low
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
6. Make the smallest doc-only change that fixes the verified gap.
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
