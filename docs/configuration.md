# DocMate Catalog

DocMate uses `docmate.catalog.json` as agent-readable routing context. The
agent reads it directly and chooses the repository from names, descriptions,
aliases, and paths.

Important fields:

- `repos[].path`: repository path to use as the task working context. DocMate
  discovers documentation inside this repository and discovers related code
  repositories at execution time when verification requires it.
- `repos[].description`: optional project background. The installer leaves this
  blank by default; fill it in when product scope, ownership, or domain context
  would help the agent route vague requests.
- `baseBranchCandidates`: ordered base branches for documentation repair.
  DocMate tries these when creating a temporary repair worktree. The installer
  seeds this from each repository's detected remote default branch; edit it
  after installation when documentation repair should target a different branch
  such as `develop`, `release/docs`, or `docs-main`.
- `update.mode`: `ask`, `auto`, or `off`; the installer writes this from
  `--update-mode`.

`baseBranchCandidates` belongs in the catalog because the correct base branch is
repository-specific and can differ between documentation repositories. Keep the
most likely branch first. When `update.mode` is `ask` or `auto`, the validator
requires at least one candidate so documentation repair has a deterministic
starting point.

Each catalog entry should represent one git repository or working directory. If
documentation is split across multiple independent repositories, add multiple
`repos` entries instead of grouping their paths into one entry. DocMate trusts
the agent to find documentation inside the selected repository and to discover
related code repositories when doc/code verification requires them.

Provider, branch naming, and push remote are intentionally not catalog fields.
During documentation repair, DocMate infers GitHub versus GitLab from git
remotes and available native tools, chooses a descriptive branch name, and lets
git/`gh`/`glab` use the appropriate remote context.

Validate a catalog with:

```bash
bash scripts/validate_catalog.sh ~/.agents/skills/docmate/references/docmate.catalog.json
```
