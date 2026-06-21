import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GOLDEN_CASES = ROOT / "evals" / "golden-cases.jsonl"
HARNESS = ROOT / "evals" / "run_forward_tests.py"


def test_golden_eval_cases_are_valid_and_cover_core_docmate_risks():
    allowed_decisions = {
        "docs-only ok",
        "must verify code",
        "insufficient evidence",
        "confirmed docs gap",
    }
    required_ids = {
        "missing_docs_code_has_behavior",
        "outdated_docs_default_value",
        "field_default_requires_code",
        "metrics_labels_require_code",
    }

    cases = []
    for line in GOLDEN_CASES.read_text().splitlines():
        if line.strip():
            cases.append(json.loads(line))

    assert cases
    assert required_ids.issubset({case["id"] for case in cases})

    for case in cases:
        assert case["expectedDecision"] in allowed_decisions
        assert case["expectedEvidence"]
        assert case["expectedRepair"] in {
            "not_allowed",
            "allowed_when_high_confidence",
            "allowed_only_if_gap_confirmed",
        }


def test_forward_test_harness_validates_cases_and_writes_blind_prompts(tmp_path):
    validate = subprocess.run(
        [sys.executable, str(HARNESS)],
        text=True,
        capture_output=True,
        check=False,
    )

    assert validate.returncode == 0, validate.stderr
    assert "Validated" in validate.stdout

    prompt_dir = tmp_path / "prompts"
    write = subprocess.run(
        [sys.executable, str(HARNESS), "--write-prompts", str(prompt_dir)],
        text=True,
        capture_output=True,
        check=False,
    )

    assert write.returncode == 0, write.stderr
    prompt = (prompt_dir / "missing_docs_code_has_behavior.md").read_text()
    assert "retry_timeout" in prompt
    assert "expectedDecision" not in prompt
    assert "confirmed docs gap" in prompt


def test_forward_test_harness_grades_jsonl_responses(tmp_path):
    responses_path = tmp_path / "responses.jsonl"
    lines = []
    for line in GOLDEN_CASES.read_text().splitlines():
        if not line.strip():
            continue
        case = json.loads(line)
        lines.append(
            json.dumps(
                {
                    "id": case["id"],
                    "decision": case["expectedDecision"],
                    "evidence": case["expectedEvidence"],
                    "repair": case["expectedRepair"],
                    "notes": "matches expected behavior",
                }
            )
        )
    responses_path.write_text("\n".join(lines) + "\n")

    result = subprocess.run(
        [sys.executable, str(HARNESS), "--responses", str(responses_path)],
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "Graded" in result.stdout
