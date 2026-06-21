#!/usr/bin/env python3
"""Minimal DocMate forward-test harness.

The harness does not call an agent itself. It writes blind prompts for a fresh
agent run and grades the JSONL responses from that run.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CASES = Path(__file__).with_name("golden-cases.jsonl")
DEFAULT_SKILL = ROOT / "skills" / "docmate" / "SKILL.md"

ALLOWED_DECISIONS = {
    "docs-only ok",
    "must verify code",
    "insufficient evidence",
    "confirmed docs gap",
}
ALLOWED_REPAIR = {
    "not_allowed",
    "allowed_when_high_confidence",
    "allowed_only_if_gap_confirmed",
}


def load_jsonl(path: Path) -> List[Dict[str, Any]]:
    items: List[Dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            try:
                payload = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(f"{path}:{line_number}: invalid JSON: {error}") from error
            if not isinstance(payload, dict):
                raise ValueError(f"{path}:{line_number}: expected a JSON object")
            items.append(payload)
    return items


def validate_cases(cases: Iterable[Dict[str, Any]]) -> None:
    seen = set()
    for case in cases:
        case_id = require_string(case, "id")
        if case_id in seen:
            raise ValueError(f"duplicate case id: {case_id}")
        seen.add(case_id)

        require_string(case, "question")
        fixture = case.get("fixture")
        if not isinstance(fixture, dict):
            raise ValueError(f"{case_id}: fixture must be an object")

        decision = require_string(case, "expectedDecision")
        if decision not in ALLOWED_DECISIONS:
            raise ValueError(f"{case_id}: unsupported expectedDecision: {decision}")

        evidence = case.get("expectedEvidence")
        if not isinstance(evidence, list) or not evidence:
            raise ValueError(f"{case_id}: expectedEvidence must be a non-empty array")
        for entry in evidence:
            if not isinstance(entry, str) or not entry:
                raise ValueError(f"{case_id}: expectedEvidence values must be strings")

        repair = require_string(case, "expectedRepair")
        if repair not in ALLOWED_REPAIR:
            raise ValueError(f"{case_id}: unsupported expectedRepair: {repair}")


def require_string(payload: Dict[str, Any], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value:
        raise ValueError(f"{key} must be a non-empty string")
    return value


def prompt_for_case(case: Dict[str, Any], skill_path: Path) -> str:
    fixture = case["fixture"]
    return "\n".join(
        [
            f"# DocMate forward-test case: {case['id']}",
            "",
            "Use the DocMate skill at:",
            str(skill_path),
            "",
            "Answer this documentation QA task from the fixture. Do not inspect",
            "the golden-cases expected fields while answering.",
            "",
            "User question:",
            case["question"],
            "",
            "Fixture:",
            f"- Documentation evidence: {fixture.get('docs', 'none')}",
            f"- Code evidence: {fixture.get('code', 'none')}",
            f"- External evidence: {fixture.get('external', 'none')}",
            "",
            "Return exactly one JSON object with these fields:",
            "- id",
            "- decision: docs-only ok | must verify code | insufficient evidence | confirmed docs gap",
            "- evidence: array of evidence categories used, such as docs or code",
            "- repair: not_allowed | allowed_when_high_confidence | allowed_only_if_gap_confirmed",
            "- notes: one concise sentence",
            "",
        ]
    )


def write_prompts(cases: Iterable[Dict[str, Any]], output_dir: Path, skill_path: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for case in cases:
        prompt_path = output_dir / f"{case['id']}.md"
        prompt_path.write_text(prompt_for_case(case, skill_path), encoding="utf-8")


def index_responses(responses: Iterable[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    indexed: Dict[str, Dict[str, Any]] = {}
    for response in responses:
        response_id = require_string(response, "id")
        if response_id in indexed:
            raise ValueError(f"duplicate response id: {response_id}")
        indexed[response_id] = response
    return indexed


def grade(cases: Iterable[Dict[str, Any]], responses: Iterable[Dict[str, Any]]) -> List[str]:
    indexed = index_responses(responses)
    failures: List[str] = []

    for case in cases:
        case_id = case["id"]
        response = indexed.get(case_id)
        if response is None:
            failures.append(f"{case_id}: missing response")
            continue

        decision = response.get("decision")
        if decision != case["expectedDecision"]:
            failures.append(
                f"{case_id}: decision {decision!r} != {case['expectedDecision']!r}"
            )

        repair = response.get("repair")
        if repair != case["expectedRepair"]:
            failures.append(f"{case_id}: repair {repair!r} != {case['expectedRepair']!r}")

        evidence = response.get("evidence")
        if not isinstance(evidence, list):
            failures.append(f"{case_id}: evidence must be an array")
            continue
        missing = set(case["expectedEvidence"]) - {item for item in evidence if isinstance(item, str)}
        if missing:
            failures.append(f"{case_id}: missing evidence categories: {', '.join(sorted(missing))}")

    return failures


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description="Run DocMate forward-test harness utilities.")
    parser.add_argument("--cases", type=Path, default=DEFAULT_CASES)
    parser.add_argument("--skill-path", type=Path, default=DEFAULT_SKILL)
    parser.add_argument("--write-prompts", type=Path)
    parser.add_argument("--responses", type=Path)
    args = parser.parse_args(argv)

    cases = load_jsonl(args.cases)
    validate_cases(cases)

    if args.write_prompts:
        write_prompts(cases, args.write_prompts, args.skill_path)
        print(f"Wrote {len(cases)} prompts to {args.write_prompts}")

    if args.responses:
        responses = load_jsonl(args.responses)
        failures = grade(cases, responses)
        if failures:
            for failure in failures:
                print(f"FAIL {failure}", file=sys.stderr)
            return 1
        print(f"Graded {len(cases)} responses: OK")
        return 0

    if not args.write_prompts:
        print(f"Validated {len(cases)} forward-test cases: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
