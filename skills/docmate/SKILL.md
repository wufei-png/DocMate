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

## Update Modes

- `update.mode = ask`: Ask the user before any edit. Proceed only after explicit confirmation.
- `update.mode = auto`: Proceed without asking only for a high-confidence confirmed gap with clear doc and code evidence.
- `update.mode = off`: Report the gap and stop. Do not edit files.

When updates are enabled, infer the hosting provider and push remote from the selected repository's git remotes and the available native tools. If the provider or remote is ambiguous, stop and report the blocker.

## Documentation Repair Workflow

Documentation repair is part of this skill workflow. It does not require a subagent.

1. Resolve the base branch from `baseBranchCandidates`. Do not use hardcoded branch names.
2. Create a temporary git worktree from the selected base branch. Do not edit the user's main worktree.
3. Re-check the gap in the fresh worktree.
4. If upstream already fixed it, stop with `already_fixed_upstream`.
5. Create a descriptive branch name for the documentation fix.
6. Make the smallest doc-only change that fixes the verified gap.
7. Review `git status --short` and `git diff` before committing. If code or unrelated files changed, stop and report the blocker.
8. Commit, push, and open a pull request or merge request with the native tools inferred from git remotes:
   - GitHub remotes use `gh pr create`.
   - GitLab remotes use `glab mr create`.
9. Final response must include:
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
