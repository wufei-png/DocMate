# Documentation Repair Workflow

DocMate repairs documentation only after a confirmed doc/code gap.

The safe path is:

1. Answer the original question.
2. Produce a user-facing gap report with document and code evidence.
3. Follow `defaults.update.mode`. In `ask` mode, do not ask again if the user
   already confirmed repair during the answer workflow.
4. Create a temporary git worktree from a configured base branch without
   modifying or requiring a clean main worktree.
5. Stop with `already_fixed_upstream` if the target docs no longer match the
   confirmed gap.
6. Apply the smallest doc-only fix.
7. Review the changed files with `git status --short` and `git diff`.
8. Commit, push, and open a GitHub PR or GitLab MR with native git tooling.

The skill does not require a helper script. A typical repair command sequence is:

```bash
repo_root="$(git -C /path/to/docs-repo rev-parse --show-toplevel)"
branch="docs/2026-06-21-doc-gap"
worktree="/tmp/docmate-worktree"
base_branch="<first available branch from baseBranchCandidates>"
push_remote="$(git -C "$repo_root" remote | head -n 1)"

git -C "$repo_root" worktree add -b "$branch" "$worktree" "$base_branch"

# Edit only docs in "$worktree", then review the patch before publishing.
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
