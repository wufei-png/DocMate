import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import List, Optional


ROOT = Path(__file__).resolve().parents[1]


def node_path() -> str:
    found = shutil.which("node")
    if found:
        return str(Path(found).parent)
    candidates = sorted(Path.home().glob(".nvm/versions/node/*/bin/node"))
    assert candidates, "node is required for installer tests"
    return str(candidates[-1].parent)


def fake_bin(tmp_path: Path, names: List[str]) -> Path:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for name in names:
        path = bin_dir / name
        path.write_text("#!/usr/bin/env bash\nexit 0\n")
        path.chmod(0o755)
    return bin_dir


def run_install_args(home: Path, args: List[str], extra_path: Optional[Path] = None):
    env = os.environ.copy()
    bin_dir = fake_bin(home, ["openclaw", "claude", "opencode", "codex", "hermes"])
    env["HOME"] = str(home)
    path_entries = [str(bin_dir), node_path(), env["PATH"]]
    if extra_path:
        path_entries.insert(0, str(extra_path))
    env["PATH"] = ":".join(path_entries)
    env["DOCMATE_USE_LOCAL_CACHE"] = "true"
    return subprocess.run(args, text=True, capture_output=True, env=env, check=False)


def run_install(home: Path, repo: Path, extra_args: Optional[List[str]] = None, path_flag: str = "--repo"):
    args = [
        "bash",
        str(ROOT / "scripts" / "install.sh"),
        "--yes",
        path_flag,
        str(repo),
        "--hosts",
        "all",
        "--existing",
        "backup",
    ]
    if extra_args:
        args.extend(extra_args)
    return run_install_args(home, args)


def test_global_install_creates_canonical_skill_and_all_host_links(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    repo = tmp_path / "docs-project"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)

    result = run_install(home, repo)

    assert result.returncode == 0, result.stdout + result.stderr
    canonical = home / ".agents" / "skills" / "docmate"
    assert (canonical / "SKILL.md").exists()
    assert (canonical / "references" / "docmate.catalog.json").exists()
    assert not (canonical / "references" / "docmate_update.sh").exists()

    expected_links = [
        home / ".openclaw" / "skills" / "docmate",
        home / ".claude" / "skills" / "docmate",
        home / ".config" / "opencode" / "skills" / "docmate",
        home / ".hermes" / "skills" / "software-development" / "docmate",
    ]
    for link in expected_links:
        assert link.is_symlink()
        assert link.resolve() == canonical
    assert not (home / ".codex" / "skills" / "docmate").exists()

    catalog = json.loads((canonical / "references" / "docmate.catalog.json").read_text())
    assert catalog["repos"][0]["name"] == "docs-project"
    assert catalog["repos"][0]["path"] == str(repo)
    assert set(catalog["repos"][0]["update"]) == {"mode"}
    assert catalog["repos"][0]["update"]["mode"] == "ask"


def test_existing_host_directory_is_backed_up_before_linking(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    existing = home / ".openclaw" / "skills" / "docmate"
    existing.mkdir(parents=True)
    (existing / "old.txt").write_text("old")
    repo = tmp_path / "docs-project"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)

    result = run_install(home, repo)

    assert result.returncode == 0, result.stdout + result.stderr
    backup = home / ".openclaw" / "skills" / "docmate_backup_0"
    assert backup.exists()
    assert (backup / "old.txt").read_text() == "old"
    assert existing.is_symlink()


def test_existing_canonical_directory_is_backed_up_before_reinstall(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    canonical = home / ".agents" / "skills" / "docmate"
    references = canonical / "references"
    references.mkdir(parents=True)
    (references / "docmate.catalog.json").write_text('{"custom": true}\n')
    repo = tmp_path / "docs-project"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)

    result = run_install(home, repo)

    assert result.returncode == 0, result.stdout + result.stderr
    backup = home / ".agents" / "skills" / "docmate_backup_0"
    assert backup.exists()
    assert (backup / "references" / "docmate.catalog.json").read_text() == '{"custom": true}\n'
    assert (canonical / "SKILL.md").exists()
    assert (canonical / "references" / "docmate.catalog.json").exists()


def test_installer_generates_valid_starter_catalog(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    repo = tmp_path / "gitlab-docs"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)

    result = run_install(home, repo)
    catalog = home / ".agents" / "skills" / "docmate" / "references" / "docmate.catalog.json"
    validate = subprocess.run(
        ["bash", str(ROOT / "scripts" / "validate_catalog.sh"), str(catalog)],
        text=True,
        capture_output=True,
        check=False,
        env={**os.environ, "PATH": f"{node_path()}:{os.environ['PATH']}"},
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert validate.returncode == 0, validate.stderr
    assert json.loads(catalog.read_text())["repos"][0]["update"] == {"mode": "ask"}


def test_installer_writes_selected_update_mode(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    repo = tmp_path / "docs-project"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)

    result = run_install(home, repo, ["--update-mode", "auto"])

    assert result.returncode == 0, result.stdout + result.stderr
    catalog = json.loads(
        (home / ".agents" / "skills" / "docmate" / "references" / "docmate.catalog.json").read_text()
    )
    assert catalog["defaults"]["update"]["mode"] == "auto"
    assert catalog["repos"][0]["update"]["mode"] == "auto"


def test_installer_uses_local_head_when_remote_default_is_unavailable(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    repo = tmp_path / "docs-project"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    subprocess.run(["git", "checkout", "-q", "-b", "develop"], cwd=repo, check=True)

    result = run_install(home, repo)

    assert result.returncode == 0, result.stdout + result.stderr
    catalog = json.loads(
        (home / ".agents" / "skills" / "docmate" / "references" / "docmate.catalog.json").read_text()
    )
    assert catalog["repos"][0]["baseBranchCandidates"] == ["develop"]


def test_installer_uses_glab_for_private_gitlab_default_branch(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    fake_tools = tmp_path / "fake-tools"
    fake_tools.mkdir()
    glab = fake_tools / "glab"
    glab.write_text("#!/usr/bin/env bash\nprintf 'release/docs\\n'\n")
    glab.chmod(0o755)

    repo = tmp_path / "gitlab-docs"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    subprocess.run(
        ["git", "remote", "add", "origin", "https://gitlab.sz.sensetime.com/example/gitlab-docs.git"],
        cwd=repo,
        check=True,
    )

    result = run_install_args(
        home,
        [
            "bash",
            str(ROOT / "scripts" / "install.sh"),
            "--yes",
            "--repo",
            str(repo),
            "--hosts",
            "all",
            "--existing",
            "backup",
        ],
        extra_path=fake_tools,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    catalog = json.loads(
        (home / ".agents" / "skills" / "docmate" / "references" / "docmate.catalog.json").read_text()
    )
    assert catalog["repos"][0]["baseBranchCandidates"] == ["release/docs"]


def test_installer_accepts_project_as_backward_compatible_alias(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    repo = tmp_path / "docs-project"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)

    result = run_install(home, repo, path_flag="--project")

    assert result.returncode == 0, result.stdout + result.stderr
    catalog = json.loads(
        (home / ".agents" / "skills" / "docmate" / "references" / "docmate.catalog.json").read_text()
    )
    assert catalog["repos"][0]["path"] == str(repo)


def test_installer_auto_scan_adds_detected_repositories(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    scan_root = tmp_path / "scan-root"
    repo_a = scan_root / "team-a" / "docs-a"
    repo_b = scan_root / "team-b" / "docs-b"
    repo_a.mkdir(parents=True)
    repo_b.mkdir(parents=True)
    subprocess.run(["git", "init", "-q"], cwd=repo_a, check=True)
    subprocess.run(["git", "init", "-q"], cwd=repo_b, check=True)

    result = run_install_args(
        home,
        [
            "bash",
            str(ROOT / "scripts" / "install.sh"),
            "--yes",
            "--auto-scan",
            "--scan-root",
            str(scan_root),
            "--hosts",
            "all",
            "--existing",
            "backup",
        ],
    )

    assert result.returncode == 0, result.stdout + result.stderr
    catalog = json.loads(
        (home / ".agents" / "skills" / "docmate" / "references" / "docmate.catalog.json").read_text()
    )
    assert {repo["path"] for repo in catalog["repos"]} == {str(repo_a), str(repo_b)}


def test_installer_falls_back_to_scanning_when_repo_arg_is_prefix_directory(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    prefix = tmp_path / "prefix"
    repo_a = prefix / "a"
    repo_b = prefix / "b"
    repo_a.mkdir(parents=True)
    repo_b.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo_a, check=True)
    subprocess.run(["git", "init", "-q"], cwd=repo_b, check=True)

    result = run_install(home, prefix)

    assert result.returncode == 0, result.stdout + result.stderr
    assert f"Warning: {prefix} is not a git repository" in result.stdout
    assert "Detected repositories under" in result.stdout
    catalog = json.loads(
        (home / ".agents" / "skills" / "docmate" / "references" / "docmate.catalog.json").read_text()
    )
    assert {repo["name"] for repo in catalog["repos"]} == {"a", "b"}
