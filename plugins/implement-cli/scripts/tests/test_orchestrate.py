"""Tests for implement_cli.orchestrate."""

from implement_cli.orchestrate import (
    has_actionable_findings,
    parse_pr_number,
)


class TestParsePrNumber:
    def test_pr_number_format(self) -> None:
        assert parse_pr_number("PR_NUMBER: 42") == 42

    def test_hash_format(self) -> None:
        assert parse_pr_number("Created PR #99") == 99

    def test_no_match(self) -> None:
        assert parse_pr_number("No PR created") is None

    def test_pr_number_in_longer_text(self) -> None:
        text = "Some output\nPR_NUMBER: 123\nPR_TITLE: feat: something"
        assert parse_pr_number(text) == 123


class TestHasActionableFindings:
    def test_no_findings(self) -> None:
        text = "The code is correct. No issues found."
        assert has_actionable_findings(text) is False

    def test_has_action_required(self) -> None:
        text = "### Action Required\n- Missing null check at main.py:42"
        assert has_actionable_findings(text) is True

    def test_has_recommended(self) -> None:
        text = "### Recommended\n- Consider using a context manager"
        assert has_actionable_findings(text) is True

    def test_explicit_no_actionable_findings(self) -> None:
        text = "### Action Required\nNo actionable findings in this round."
        assert has_actionable_findings(text) is False

    def test_looks_solid(self) -> None:
        text = "Architecture looks solid. No concerns."
        assert has_actionable_findings(text) is False

    def test_empty_text(self) -> None:
        assert has_actionable_findings("") is False
