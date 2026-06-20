# DocMate

DocMate is a skill-first documentation QA and documentation repair assistant for
agent hosts. It helps an agent answer from project documentation, verify gaps
against code, and optionally repair documentation by opening a GitHub pull
request or GitLab merge request.

## What It Does

- Installs as a skill for OpenClaw, Claude Code, OpenCode, Codex, and Hermes.
- Uses `~/.agents/skills/docmate` as the canonical install for Global and
  Custom installs; Codex reads that canonical skill directory directly.
- Uses an agent-readable `docmate.catalog.json` as a repository catalog.
- Routes to a configured repository path, then lets the agent discover
  documentation and related code evidence during the task.
- Reports documentation gaps with document evidence, code evidence, affected
  docs, and confidence.
- Supports `ask`, `auto`, and `off` modes for documentation repair.
- Uses temporary git worktrees so documentation repair does not dirty the user's
  main checkout.
- Opens GitHub PRs with `gh` and GitLab MRs with `glab`.

## Quick Start

One-line install:

```bash
curl -fsSL https://raw.githubusercontent.com/wufei-png/DocMate/main/scripts/install.sh | bash
```

Non-interactive install with explicit repositories:

```bash
bash scripts/install.sh --yes --repo /absolute/path/to/docs-repo --update-mode ask
```

Non-interactive install with repository auto scan:

```bash
bash scripts/install.sh --yes --auto-scan --scan-root /absolute/path/to/repo-prefix --scan-depth 2
```

Auto scan defaults to depth `2`. In interactive installs, the installer asks for
the scan depth after the prefix directory; for scripts, use `--scan-depth N` or
`DOCMATE_SCAN_MAX_DEPTH=N`.

Install target modes:

- `global` (default): install once to `~/.agents/skills/docmate` and link
  detected agent hosts.
- `single`: install directly to one host, for example
  `--install-mode single --hosts openclaw`.
- `custom`: install once to `~/.agents/skills/docmate` and link the hosts
  selected by `--hosts`, for example `--hosts openclaw,codex`.
- `--hosts all` remains supported for script compatibility and selects every
  supported host.

Then edit:

```text
~/.agents/skills/docmate/references/docmate.catalog.json
```

For `single` installs, use the `Catalog:` path printed by the installer instead.

Add repository aliases, descriptions, base branch candidates, and update mode.
The installer seeds `baseBranchCandidates` from each repository's detected
remote default branch; edit it only when the repair base should differ.

## Validation

```bash
bash scripts/validate_catalog.sh ~/.agents/skills/docmate/references/docmate.catalog.json
python3 -m pytest -q
```

## License

MIT. See [LICENSE](LICENSE).
