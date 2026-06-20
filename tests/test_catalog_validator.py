import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run_validator(catalog_path: Path):
    return subprocess.run(
        ["bash", str(ROOT / "scripts" / "validate_catalog.sh"), str(catalog_path)],
        text=True,
        capture_output=True,
        check=False,
    )


def valid_catalog(tmp_path: Path) -> dict:
    docs = tmp_path / "docs"
    runbooks = tmp_path / "runbooks"
    docs.mkdir()
    runbooks.mkdir()
    return {
        "schemaVersion": 2,
        "installHosts": ["openclaw", "claude-code", "opencode", "codex", "hermes"],
        "defaults": {
            "update": {
                "mode": "ask",
            }
        },
        "repos": [
            {
                "name": "docs-site",
                "description": "Public documentation site.",
                "path": str(docs),
                "aliases": ["docs", "site"],
                "baseBranchCandidates": ["main"],
                "update": {
                    "mode": "ask",
                },
            },
            {
                "name": "runbooks",
                "description": "Operational runbooks.",
                "path": str(runbooks),
                "aliases": ["ops-docs"],
                "baseBranchCandidates": ["main"],
                "update": {
                    "mode": "auto",
                },
            },
        ],
    }


def write_catalog(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n")


def test_accepts_valid_catalog_with_multiple_repos(tmp_path):
    catalog_path = tmp_path / "docmate.catalog.json"
    write_catalog(catalog_path, valid_catalog(tmp_path))

    result = run_validator(catalog_path)

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "OK"


def test_rejects_relative_paths(tmp_path):
    payload = valid_catalog(tmp_path)
    payload["repos"][0]["path"] = "docs"
    catalog_path = tmp_path / "docmate.catalog.json"
    write_catalog(catalog_path, payload)

    result = run_validator(catalog_path)

    assert result.returncode != 0
    assert "repos[0].path must be an absolute path" in result.stderr


def test_rejects_duplicate_repo_paths(tmp_path):
    payload = valid_catalog(tmp_path)
    payload["repos"][1]["path"] = payload["repos"][0]["path"]
    catalog_path = tmp_path / "docmate.catalog.json"
    write_catalog(catalog_path, payload)

    result = run_validator(catalog_path)

    assert result.returncode != 0
    assert "duplicate repository path" in result.stderr


def test_rejects_duplicate_aliases(tmp_path):
    payload = valid_catalog(tmp_path)
    payload["repos"][0]["aliases"] = ["docs", "docs"]
    catalog_path = tmp_path / "docmate.catalog.json"
    write_catalog(catalog_path, payload)

    result = run_validator(catalog_path)

    assert result.returncode != 0
    assert "duplicate alias" in result.stderr


def test_rejects_cross_repo_duplicate_aliases(tmp_path):
    payload = valid_catalog(tmp_path)
    payload["repos"][0]["aliases"] = ["docs"]
    payload["repos"][1]["aliases"] = ["docs"]
    catalog_path = tmp_path / "docmate.catalog.json"
    write_catalog(catalog_path, payload)

    result = run_validator(catalog_path)

    assert result.returncode != 0
    assert "alias already used by repository docs-site: docs" in result.stderr


def test_rejects_unsupported_update_keys(tmp_path):
    payload = valid_catalog(tmp_path)
    payload["repos"][0]["update"]["branchPrefix"] = "docmate/"
    catalog_path = tmp_path / "docmate.catalog.json"
    write_catalog(catalog_path, payload)

    result = run_validator(catalog_path)

    assert result.returncode != 0
    assert "repos[0].update.branchPrefix is not supported" in result.stderr


def test_rejects_invalid_update_mode(tmp_path):
    payload = valid_catalog(tmp_path)
    payload["repos"][0]["update"]["mode"] = "always"
    catalog_path = tmp_path / "docmate.catalog.json"
    write_catalog(catalog_path, payload)

    result = run_validator(catalog_path)

    assert result.returncode != 0
    assert "update.mode must be ask, auto, or off" in result.stderr


def test_rejects_empty_base_branches_when_update_enabled(tmp_path):
    payload = valid_catalog(tmp_path)
    payload["repos"][0]["baseBranchCandidates"] = []
    catalog_path = tmp_path / "docmate.catalog.json"
    write_catalog(catalog_path, payload)

    result = run_validator(catalog_path)

    assert result.returncode != 0
    assert "baseBranchCandidates must contain at least one branch when updates are enabled" in result.stderr
