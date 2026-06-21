import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path
from typing import List, Optional

import pytest


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


def run_install_args(
    home: Path,
    args: List[str],
    extra_path: Optional[Path] = None,
    input_text: Optional[str] = None,
    timeout: int = 15,
    fake_commands: Optional[List[str]] = None,
):
    env = os.environ.copy()
    if fake_commands is None:
        fake_commands = ["openclaw", "claude", "opencode", "codex", "hermes"]
    bin_dir = fake_bin(home, fake_commands)
    node_executable = Path(node_path()) / "node"
    node_wrapper = bin_dir / "node"
    node_wrapper.write_text(f"#!/usr/bin/env bash\nexec {node_executable} \"$@\"\n")
    node_wrapper.chmod(0o755)
    env["HOME"] = str(home)
    path_entries = [str(bin_dir), "/usr/bin", "/bin"]
    if extra_path:
        path_entries.insert(0, str(extra_path))
    env["PATH"] = ":".join(path_entries)
    env["DOCMATE_USE_LOCAL_CACHE"] = "true"
    return subprocess.run(
        args,
        text=True,
        input=input_text,
        capture_output=True,
        env=env,
        check=False,
        timeout=timeout,
    )


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


def test_piped_installer_without_repo_exits_when_interactive_input_is_unavailable(tmp_path):
    home = tmp_path / "home"
    home.mkdir()

    result = run_install_args(
        home,
        [
            "bash",
        ],
        input_text=(ROOT / "scripts" / "install.sh").read_text(),
        timeout=5,
    )

    assert result.returncode != 0
    assert "no repositories selected" in result.stderr
    assert "BASH_SOURCE" not in result.stderr
    assert "Invalid choice" not in result.stdout


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
    assert catalog["repos"][0]["description"] == ""
    assert catalog["repos"][0]["path"] == str(repo)
    assert "update" not in catalog["repos"][0]
    assert catalog["defaults"]["update"]["mode"] == "auto"
    assert "Optional catalog enrichment" in result.stdout
    assert "repos[].description" in result.stdout
    assert "repos[].aliases" in result.stdout
    assert "repos[].baseBranchCandidates" in result.stdout


def test_yes_without_hosts_uses_global_detected_hosts(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    repo = tmp_path / "docs-project"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)

    result = run_install_args(
        home,
        [
            "bash",
            str(ROOT / "scripts" / "install.sh"),
            "--yes",
            "--repo",
            str(repo),
            "--existing",
            "backup",
        ],
        fake_commands=["opencode", "codex"],
    )

    assert result.returncode == 0, result.stdout + result.stderr
    canonical = home / ".agents" / "skills" / "docmate"
    assert (canonical / "SKILL.md").exists()
    assert (home / ".config" / "opencode" / "skills" / "docmate").is_symlink()
    assert not (home / ".openclaw" / "skills" / "docmate").exists()
    assert not (home / ".claude" / "skills" / "docmate").exists()
    assert not (home / ".hermes" / "skills" / "software-development" / "docmate").exists()

    catalog = json.loads((canonical / "references" / "docmate.catalog.json").read_text())
    assert catalog["installHosts"] == ["opencode", "codex"]


def test_single_host_install_writes_directly_to_selected_host(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    repo = tmp_path / "docs-project"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)

    result = run_install_args(
        home,
        [
            "bash",
            str(ROOT / "scripts" / "install.sh"),
            "--yes",
            "--repo",
            str(repo),
            "--install-mode",
            "single",
            "--hosts",
            "openclaw",
            "--existing",
            "backup",
        ],
    )

    assert result.returncode == 0, result.stdout + result.stderr
    direct_target = home / ".openclaw" / "skills" / "docmate"
    assert (direct_target / "SKILL.md").exists()
    assert not direct_target.is_symlink()
    assert not (home / ".agents" / "skills" / "docmate").exists()

    catalog = json.loads((direct_target / "references" / "docmate.catalog.json").read_text())
    assert catalog["installHosts"] == ["openclaw"]


def test_interactive_single_host_menu_supports_arrow_enter_selection(tmp_path):
    if not shutil.which("script"):
        pytest.skip("script command is required for pseudo-tty installer test")

    home = tmp_path / "home"
    home.mkdir()
    repo = tmp_path / "docs-project"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)

    bin_dir = fake_bin(home, [])
    node_executable = Path(node_path()) / "node"
    node_wrapper = bin_dir / "node"
    node_wrapper.write_text(f"#!/usr/bin/env bash\nexec {node_executable} \"$@\"\n")
    node_wrapper.chmod(0o755)

    env = os.environ.copy()
    env["HOME"] = str(home)
    env["PATH"] = f"{bin_dir}:/usr/bin:/bin"
    env["DOCMATE_USE_LOCAL_CACHE"] = "true"
    env["TERM"] = "xterm"

    command = (
        f"bash {shlex.quote(str(ROOT / 'scripts' / 'install.sh'))} "
        f"--repo {shlex.quote(str(repo))} --update-mode auto --install-mode single --existing overwrite"
    )
    result = subprocess.run(
        ["script", "-qfec", command, "/dev/null"],
        text=True,
        input="\x1b[B\x1b[B\r",
        capture_output=True,
        env=env,
        check=False,
        timeout=15,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "Use Up/Down to move, Space or Enter to select." in result.stdout
    assert (home / ".config" / "opencode" / "skills" / "docmate" / "SKILL.md").exists()
    assert not (home / ".openclaw" / "skills" / "docmate").exists()


def test_interactive_update_mode_menu_writes_global_default(tmp_path):
    if not shutil.which("script"):
        pytest.skip("script command is required for pseudo-tty installer test")

    home = tmp_path / "home"
    home.mkdir()
    repo = tmp_path / "docs-project"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)

    bin_dir = fake_bin(home, [])
    node_executable = Path(node_path()) / "node"
    node_wrapper = bin_dir / "node"
    node_wrapper.write_text(f"#!/usr/bin/env bash\nexec {node_executable} \"$@\"\n")
    node_wrapper.chmod(0o755)

    env = os.environ.copy()
    env["HOME"] = str(home)
    env["PATH"] = f"{bin_dir}:/usr/bin:/bin"
    env["DOCMATE_USE_LOCAL_CACHE"] = "true"
    env["TERM"] = "xterm"

    command = (
        f"bash {shlex.quote(str(ROOT / 'scripts' / 'install.sh'))} "
        f"--repo {shlex.quote(str(repo))} --hosts codex --existing overwrite"
    )
    result = subprocess.run(
        ["script", "-qfec", command, "/dev/null"],
        text=True,
        input="\x1b[B\r",
        capture_output=True,
        env=env,
        check=False,
        timeout=15,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "Documentation repair mode" in result.stdout
    catalog = json.loads(
        (home / ".agents" / "skills" / "docmate" / "references" / "docmate.catalog.json").read_text()
    )
    assert catalog["defaults"]["update"]["mode"] == "ask"
    assert "update" not in catalog["repos"][0]


def test_duplicate_repo_names_keep_first_in_non_interactive_install(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    repo_a = tmp_path / "team-a" / "open-webui"
    repo_b = tmp_path / "team-b" / "open-webui"
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
            "--repo",
            str(repo_a),
            "--repo",
            str(repo_b),
            "--hosts",
            "codex",
            "--existing",
            "backup",
        ],
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "duplicate repository name detected: open-webui" in result.stdout
    assert "duplicate repository name" not in result.stderr

    catalog = json.loads(
        (home / ".agents" / "skills" / "docmate" / "references" / "docmate.catalog.json").read_text()
    )
    assert [repo["path"] for repo in catalog["repos"]] == [str(repo_a)]


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
    generated = json.loads(catalog.read_text())
    repo_entry = generated["repos"][0]
    assert repo_entry["description"] == ""
    assert "update" not in repo_entry
    assert generated["defaults"]["update"]["mode"] == "auto"


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
    assert "update" not in catalog["repos"][0]


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
            "--scan-depth",
            "3",
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


def test_installer_auto_scan_default_depth_is_two(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    scan_root = tmp_path / "scan-root"
    shallow_repo = scan_root / "docs-a"
    deep_repo = scan_root / "team-b" / "docs-b"
    shallow_repo.mkdir(parents=True)
    deep_repo.mkdir(parents=True)
    subprocess.run(["git", "init", "-q"], cwd=shallow_repo, check=True)
    subprocess.run(["git", "init", "-q"], cwd=deep_repo, check=True)

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
            "codex",
            "--existing",
            "backup",
        ],
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert "max depth: 2" in result.stdout
    catalog = json.loads(
        (home / ".agents" / "skills" / "docmate" / "references" / "docmate.catalog.json").read_text()
    )
    assert [repo["path"] for repo in catalog["repos"]] == [str(shallow_repo)]


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
