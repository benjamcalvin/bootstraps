"""Tests for implement_cli.prompts."""

import pytest

from implement_cli.prompts import PROMPTS_DIR, load_prompt


def test_prompts_dir_exists() -> None:
    assert PROMPTS_DIR.exists()
    assert PROMPTS_DIR.is_dir()


def test_load_prompt_plan() -> None:
    result = load_prompt("plan", TASK_DESCRIPTION="Build a widget")
    assert "Build a widget" in result
    assert "$TASK_DESCRIPTION" not in result


def test_load_prompt_implement() -> None:
    result = load_prompt(
        "implement",
        TASK_DESCRIPTION="Fix the bug",
        ISSUE_NUMBER="42",
    )
    assert "Fix the bug" in result
    assert "42" in result


def test_load_prompt_review_correctness() -> None:
    result = load_prompt(
        "review-correctness",
        PR_NUMBER="99",
        ROUND_NUMBER="2",
    )
    assert "99" in result
    assert "round 2" in result.lower() or "2" in result


def test_load_prompt_address() -> None:
    result = load_prompt(
        "address",
        PR_NUMBER="55",
        ROUND_NUMBER="1",
        FINDINGS_PATH="/tmp/findings.md",
    )
    assert "55" in result
    assert "/tmp/findings.md" in result


def test_load_prompt_all_templates_exist() -> None:
    templates = [
        "plan",
        "implement",
        "review-correctness",
        "review-security",
        "review-architecture",
        "review-testing",
        "review-docs",
        "address",
        "verify",
        "merge",
    ]
    for name in templates:
        prompt = load_prompt(name)
        assert len(prompt) > 0, f"Template {name} is empty"


def test_load_prompt_missing_template() -> None:
    with pytest.raises(FileNotFoundError):
        load_prompt("nonexistent-template")


def test_load_prompt_rejects_path_traversal() -> None:
    with pytest.raises(ValueError, match="resolves outside prompts directory"):
        load_prompt("../../etc/passwd")


def test_load_prompt_no_variables() -> None:
    result = load_prompt("plan")
    assert "$TASK_DESCRIPTION" in result  # Variable not replaced without kwarg


def test_load_prompt_multiple_variables() -> None:
    result = load_prompt(
        "verify",
        PR_NUMBER="123",
    )
    assert "123" in result
    assert "$PR_NUMBER" not in result
