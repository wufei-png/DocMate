import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GOLDEN_CASES = ROOT / "evals" / "golden-cases.jsonl"


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
