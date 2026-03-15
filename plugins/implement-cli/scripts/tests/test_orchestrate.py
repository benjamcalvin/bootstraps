"""Tests for implement_cli.orchestrate."""

import argparse
from pathlib import Path

from implement_cli.orchestrate import (
    build_config,
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


class TestBuildConfig:
    def _make_args(self, **overrides) -> argparse.Namespace:
        defaults = {
            "task": "implement something",
            "cwd": ".",
            "skip_planning": False,
            "reviewers": None,
            "max_rounds": 10,
            "pr": None,
            "phases": None,
        }
        defaults.update(overrides)
        return argparse.Namespace(**defaults)

    def test_freeform_task(self) -> None:
        config = build_config(self._make_args(task="fix the login bug"))
        assert config.task_description == "fix the login bug"
        assert config.issue_number is None
        assert config.pr_number is None

    def test_issue_number_parsing(self) -> None:
        config = build_config(self._make_args(task="#42 fix the login bug"))
        assert config.issue_number == 42
        assert config.task_description == "#42 fix the login bug"

    def test_invalid_issue_number(self) -> None:
        config = build_config(self._make_args(task="#abc not a number"))
        assert config.issue_number is None

    def test_bare_hash_does_not_crash(self) -> None:
        config = build_config(self._make_args(task="#"))
        assert config.issue_number is None

    def test_hash_with_spaces_does_not_crash(self) -> None:
        config = build_config(self._make_args(task="# "))
        assert config.issue_number is None

    def test_pr_number_from_args(self) -> None:
        config = build_config(self._make_args(pr=99))
        assert config.pr_number == 99

    def test_default_reviewers(self) -> None:
        config = build_config(self._make_args())
        assert "review-correctness" in config.reviewers
        assert "review-security" in config.reviewers
        assert len(config.reviewers) == 4

    def test_custom_reviewers(self) -> None:
        config = build_config(self._make_args(reviewers=["review-correctness"]))
        assert config.reviewers == ["review-correctness"]

    def test_cwd_resolved(self) -> None:
        config = build_config(self._make_args(cwd="."))
        assert Path(config.cwd).is_absolute()

    def test_skip_planning(self) -> None:
        config = build_config(self._make_args(skip_planning=True))
        assert config.skip_planning is True

    def test_max_rounds(self) -> None:
        config = build_config(self._make_args(max_rounds=5))
        assert config.max_review_rounds == 5


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

    def test_findings_header_takes_precedence(self) -> None:
        # Even if "no actionable findings" appears, the header means findings exist
        text = "### Action Required\nNo actionable findings in this round."
        assert has_actionable_findings(text) is True

    def test_plain_text_without_findings_headers(self) -> None:
        text = "Architecture looks solid. No concerns."
        assert has_actionable_findings(text) is False

    def test_empty_text(self) -> None:
        assert has_actionable_findings("") is False

    def test_findings_with_summary_containing_praise(self) -> None:
        """Findings should not be suppressed by praise phrases in summary."""
        text = (
            "### Action Required\n"
            "- Bug at line 42\n\n"
            "### Summary\n"
            "The code is correct except for the above issue."
        )
        assert has_actionable_findings(text) is True

    def test_no_findings_phrase_without_headers(self) -> None:
        text = "No issues found. Everything looks good."
        assert has_actionable_findings(text) is False

    def test_minor_heading_not_treated_as_findings(self) -> None:
        """### Minor alone does not trigger actionable findings."""
        text = "### Minor\n- Consider renaming the variable"
        assert has_actionable_findings(text) is False
