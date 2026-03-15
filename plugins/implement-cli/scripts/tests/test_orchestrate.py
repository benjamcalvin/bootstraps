"""Tests for implement_cli.orchestrate."""

import argparse

from implement_cli.orchestrate import (
    _has_actionable_findings,
    build_config,
    parse_args,
    parse_pr_number,
)


class TestParseArgs:
    def test_minimal(self) -> None:
        args = parse_args(["Fix the bug"])
        assert args.task == "Fix the bug"
        assert args.cwd == "."
        assert args.skip_planning is False
        assert args.reviewers is None
        assert args.max_rounds == 10
        assert args.pr is None
        assert args.verbose is False

    def test_all_flags(self) -> None:
        args = parse_args([
            "Build feature",
            "--cwd", "/tmp/project",
            "--skip-planning",
            "--reviewers", "review-correctness", "review-security",
            "--max-rounds", "5",
            "--pr", "42",
            "-v",
        ])
        assert args.task == "Build feature"
        assert args.cwd == "/tmp/project"
        assert args.skip_planning is True
        assert args.reviewers == ["review-correctness", "review-security"]
        assert args.max_rounds == 5
        assert args.pr == 42
        assert args.verbose is True

    def test_phases(self) -> None:
        args = parse_args(["task", "--phases", "review", "docs"])
        assert args.phases == ["review", "docs"]


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
    def test_basic(self) -> None:
        args = parse_args(["Fix the bug"])
        config = build_config(args)
        assert config.task_description == "Fix the bug"
        assert config.issue_number is None
        assert config.pr_number is None
        assert config.skip_planning is False
        assert len(config.reviewers) == 4

    def test_issue_number(self) -> None:
        args = parse_args(["#44 Build feature"])
        config = build_config(args)
        assert config.issue_number == 44

    def test_pr_override(self) -> None:
        args = parse_args(["task", "--pr", "55"])
        config = build_config(args)
        assert config.pr_number == 55

    def test_custom_reviewers(self) -> None:
        args = parse_args(["task", "--reviewers", "review-correctness"])
        config = build_config(args)
        assert config.reviewers == ["review-correctness"]


class TestHasActionableFindings:
    def test_no_findings(self) -> None:
        text = "The code is correct. No issues found."
        assert _has_actionable_findings(text) is False

    def test_has_action_required(self) -> None:
        text = "### Action Required\n- Missing null check at main.py:42"
        assert _has_actionable_findings(text) is True

    def test_has_recommended(self) -> None:
        text = "### Recommended\n- Consider using a context manager"
        assert _has_actionable_findings(text) is True

    def test_explicit_no_actionable_findings(self) -> None:
        text = "### Action Required\nNo actionable findings in this round."
        assert _has_actionable_findings(text) is False

    def test_looks_solid(self) -> None:
        text = "Architecture looks solid. No concerns."
        assert _has_actionable_findings(text) is False

    def test_empty_text(self) -> None:
        assert _has_actionable_findings("") is False
