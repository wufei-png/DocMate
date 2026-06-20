# Install DocMate

DocMate installs as a skill. It does not modify a user's main agent prompts,
workspace identity files, or memory files.

One-line install from GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/wufei-png/DocMate/main/scripts/install.sh | bash
```

Install from a local clone with explicit repositories:

```bash
bash scripts/install.sh --yes --repo /absolute/path/to/docs-repo --hosts all --update-mode ask
```

Install from a local clone by scanning a repository prefix directory:

```bash
bash scripts/install.sh --yes --auto-scan --scan-root /absolute/path/to/repo-prefix
```

Use `--update-mode ask`, `--update-mode auto`, or `--update-mode off` to choose
whether documentation repair asks before editing, opens PRs/MRs automatically
for high-confidence gaps, or only reports gaps.

The canonical install path is:

```text
~/.agents/skills/docmate
```

The installer links that directory into supported host skill locations for
OpenClaw, Claude Code, OpenCode, and Hermes. Codex uses the canonical
`~/.agents/skills/docmate` directory directly, so the `codex` host does not
create a separate `~/.codex` link.

After installation, edit:

```text
~/.agents/skills/docmate/references/docmate.catalog.json
```

`--project PATH` is still accepted as a backward-compatible alias for
`--repo PATH`.

When a `--repo` path is not itself a git repository, the installer scans under
that path for git repositories, prints the detected candidates, and asks before
adding them. With `--yes`, detected repositories are added automatically.
