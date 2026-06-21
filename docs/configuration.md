# DocMate Catalog

DocMate uses `docmate.catalog.json` as agent-readable routing context. The
agent reads it directly and chooses the repository from names, descriptions,
aliases, and paths.

Important fields:

- `repos[].path`: repository path to use as the task working context. DocMate
  discovers documentation inside this repository and discovers related code
  repositories at execution time when verification requires it.
- `repos[].description`: optional project background. Add it when product
  scope, ownership, or domain context would help the agent route vague requests.
- `repos[].aliases`: optional short names users may type for this repository.
- `baseBranchCandidates`: ordered base branches for documentation repair.
  DocMate tries these when creating a temporary repair worktree. The installer
  seeds this from each repository's detected remote default branch with `gh`,
  `glab`, or `git`, then local HEAD, then fallback `main`; edit it after
  installation when documentation repair should target a different branch such
  as `develop`, `release/docs`, or `docs-main`.
- `defaults.update.mode`: global documentation repair mode for all repositories.
  `ask` is the installer default; use `auto` to repair high-confidence confirmed
  gaps without asking, or `off` to report gaps without editing.

`baseBranchCandidates` belongs in the catalog because the correct base branch is
repository-specific and can differ between documentation repositories. Keep the
most likely branch first. When `defaults.update.mode` is `ask` or `auto`, the
validator requires at least one candidate so documentation repair has a
deterministic starting point.

Repository-level `update.mode` values are intentionally not supported. Repair
behavior is one global install setting under `defaults.update.mode`.

Each catalog entry should represent one git repository or working directory. If
documentation is split across multiple independent repositories, add multiple
`repos` entries instead of grouping their paths into one entry. DocMate trusts
the agent to find documentation inside the selected repository and to discover
related code repositories when doc/code verification requires them.

Provider, branch naming, and push remote are intentionally not catalog fields.
During documentation repair, DocMate infers GitHub versus GitLab from git
remotes and available native tools, chooses a descriptive branch name, and lets
git/`gh`/`glab` use the appropriate remote context.

New catalogs contain only runtime routing and repair fields. Older catalogs may
still include `installHosts`; the validator accepts it for compatibility, but
the skill does not use it.

Validate a catalog with:

```bash
bash scripts/validate_catalog.sh ~/.agents/skills/docmate/references/docmate.catalog.json
```
