"""Tests for implement_cli.review."""

import asyncio
from unittest.mock import AsyncMock, patch

import pytest

from implement_cli.review import REVIEWER_NAMES, run_parallel_reviewers, run_reviewer
from implement_cli.sdk import AgentResult
from implement_cli.tracking import CostLimitError, RunContext


class TestReviewerValidation:
    def test_valid_reviewer_names(self) -> None:
        assert "review-correctness" in REVIEWER_NAMES
        assert "review-security" in REVIEWER_NAMES
        assert "review-docs" in REVIEWER_NAMES

    @patch("implement_cli.review.run_agent")
    @patch("implement_cli.review.load_prompt", return_value="prompt")
    def test_invalid_reviewer_rejected(self, mock_prompt, mock_agent) -> None:
        with pytest.raises(ValueError, match="Unknown reviewer"):
            asyncio.run(run_reviewer(
                "../../etc/passwd",
                pr_number=1,
                round_number=1,
                cwd="/tmp",
            ))
        mock_agent.assert_not_called()


class TestRunParallelReviewers:
    @patch("implement_cli.review.run_agent")
    @patch("implement_cli.review.load_prompt", return_value="prompt")
    def test_exception_creates_error_result(self, mock_prompt, mock_agent) -> None:
        mock_agent.side_effect = RuntimeError("SDK crashed")

        results = asyncio.run(run_parallel_reviewers(
            ["review-correctness"],
            pr_number=1,
            round_number=1,
            cwd="/tmp",
        ))

        assert results["review-correctness"].is_error is True
        assert "failed with an exception" in results["review-correctness"].text

    @patch("implement_cli.review.run_agent")
    @patch("implement_cli.review.load_prompt", return_value="prompt")
    def test_cost_limit_propagates(self, mock_prompt, mock_agent) -> None:
        mock_agent.side_effect = CostLimitError("cost exceeded")

        with pytest.raises(CostLimitError):
            asyncio.run(run_parallel_reviewers(
                ["review-correctness"],
                pr_number=1,
                round_number=1,
                cwd="/tmp",
            ))

    @patch("implement_cli.review.run_agent")
    @patch("implement_cli.review.load_prompt", return_value="prompt")
    def test_successful_parallel_run(self, mock_prompt, mock_agent) -> None:
        async def mock_run(*args, **kwargs):
            return AgentResult(text="findings", session_id="s1")

        mock_agent.side_effect = mock_run

        results = asyncio.run(run_parallel_reviewers(
            ["review-correctness", "review-security"],
            pr_number=1,
            round_number=1,
            cwd="/tmp",
        ))

        assert len(results) == 2
        assert "review-correctness" in results
        assert "review-security" in results
        assert results["review-correctness"].text == "findings"
