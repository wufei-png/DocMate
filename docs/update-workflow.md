# Documentation Repair Workflow

DocMate repairs documentation only after a confirmed doc/code gap.

## Design Decision: No Repair Subagent

Documentation repair stays in the DocMate skill workflow instead of being split
into a subagent. The repair path needs the selected repository, evidence chain,
gap classification, user confirmation or `defaults.update.mode` state, and
handoff context to remain in one responsibility boundary. Splitting this into a
subagent would make it easier to lose repo context, evidence provenance, or the
confirmation state that gates edits and PR/MR creation.

A repair subagent should be reconsidered only after DocMate has an explicit
serialized handoff contract and eval coverage proving that evidence, target
repository, target docs, and user-confirmation state survive the handoff
without ambiguity.

The safe path is:

1. Answer the original question.
2. Produce a gap report with document and code evidence.
3. Follow `defaults.update.mode`.
4. Prepare the repair handoff from `references/repair-handoff.template.md`.
5. Create a temporary git worktree from a configured base branch.
6. Re-check the gap in that worktree.
7. Apply a doc-only fix.
8. Review the changed files with `git status --short` and `git diff`.
9. Commit, push, and open a GitHub PR or GitLab MR with native git tooling.

The skill does not require a helper script. A typical repair command sequence is:

```bash
repo_root="$(git -C /path/to/docs-repo rev-parse --show-toplevel)"
branch="docs/2026-06-21-doc-gap"
worktree="/tmp/docmate-worktree"
base_branch="<first available branch from baseBranchCandidates>"
push_remote="$(git -C "$repo_root" remote | head -n 1)"

git -C "$repo_root" worktree add -b "$branch" "$worktree" "$base_branch"

# Edit docs in "$worktree", then review the patch before publishing.
git -C "$worktree" status --short
git -C "$worktree" diff
git -C "$worktree" add <changed-doc-files>
git -C "$worktree" commit -m "docs: fix documented behavior"
git -C "$worktree" push -u "$push_remote" "$branch"

# GitHub:
gh pr create \
  --base "$base_branch" \
  --head "$branch" \
  --title "Fix documented behavior" \
  --body "Created by DocMate."

# GitLab:
glab mr create \
  --target-branch "$base_branch" \
  --source-branch "$branch" \
  --title "Fix documented behavior" \
  --description "Created by DocMate."
```
