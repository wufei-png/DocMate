from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skills" / "docmate" / "SKILL.md"


def test_skill_frontmatter_and_trigger_description_cover_docmate_workflow():
    content = SKILL.read_text()

    assert "name: docmate" in content
    assert "documentation QA" in content
    assert "documentation gaps" in content
    assert "pull request" in content
    assert "merge request" in content


def test_skill_requires_catalog_before_repo_selection():
    content = SKILL.read_text()

    assert "references/docmate.catalog.json" in content
    assert "before selecting a repository" in content
    assert "aliases" in content
    assert "path" in content
    assert "docRoots" not in content
    assert "codeRoots" not in content


def test_skill_has_gap_report_and_update_mode_rules():
    content = SKILL.read_text()

    assert "Gap report" in content
    assert "update.mode = ask" in content
    assert "update.mode = auto" in content
    assert "update.mode = off" in content
    assert "already_fixed_upstream" in content
    assert "docmate_update.sh" not in content


def test_skill_has_no_internal_project_terms():
    content = SKILL.read_text()

    forbidden = [
        "Vi" + "per",
        "VI" + "PER",
        "G1" + "-dev",
        "gitlab.sz." + "sensetime.com",
        ".openclaw/" + "workspace",
    ]
    for term in forbidden:
        assert term not in content
