# DocMate Catalog

DocMate uses `docmate.catalog.json` as agent-readable routing context. The
agent reads it directly and chooses the repository from names, descriptions,
aliases, and paths.

Important fields:

- `repos[].path`: repository path to use as the task working context. DocMate
  discovers documentation inside this repository and discovers related code
  repositories at execution time when verification requires it.
- `repos[].description`: optional project background. To auto-fill missing
  descriptions, open the one-time prompt at
  `https://github.com/wufei-png/DocMate/blob/main/docs/prompts/fill-catalog-descriptions.md`,
  paste it into your own agent, and provide the actual catalog path.
- `repos[].aliases`: optional short names users may type for this repository.
  Fill aliases manually when they would help agents route ambiguous requests.
- `baseBranchCandidates`: ordered base branches for documentation repair.
  DocMate tries these when creating a temporary repair worktree. The installer
  seeds this from a remote default branch verified with `gh`, `glab`, or `git`.
  If remote detection fails, local HEAD or `main` is an unverified candidate,
  not a known remote default. Verify the remote base before repair and edit the
  candidate when needed, such as `develop`, `release/docs`, or `docs-main`.
- `defaults.update.mode`: global documentation repair mode for all repositories.
  `ask` is the installer default; use `auto` to repair high-confidence confirmed
  gaps without asking, or `off` to report gaps without editing. `auto` also
  requires a recorded, published code revision for the intended documentation
  audience; dirty/untracked or feature-branch-only behavior is local development
  evidence and cannot by itself trigger automatic publication.

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

For code-verified answers and repairs, the Skill records the docs and related
code repositories separately: path, checked `HEAD`, checked ref, and clean or
dirty worktree state. A repair report also records the intended docs remote/base
and how the code revision is published for that audience. These are task
evidence, not catalog fields. If generated documentation is involved, `auto`
also requires a known source-to-output relationship; an unknown relationship
stops automatic repair.

New catalogs contain only runtime routing and repair fields. Older catalogs may
still include `installHosts`; the validator accepts it for compatibility, but
the skill does not use it.

Validate a catalog with:

```bash
bash scripts/validate_catalog.sh ~/.agents/skills/docmate/references/docmate.catalog.json
```
