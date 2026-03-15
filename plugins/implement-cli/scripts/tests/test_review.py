"""Tests for implement_cli.review."""

import asyncio
from unittest.mock import AsyncMock, patch

import pytest

from implement_cli.review import run_parallel_reviewers, run_reviewer
from implement_cli.types import VALID_REVIEWERS
from implement_cli.sdk import AgentResult
from implement_cli.tracking import CostLimitError, RunContext


class TestReviewerValidation:
    def test_valid_reviewer_names(self) -> None:
        assert "review-correctness" in VALID_REVIEWERS
        assert "review-security" in VALID_REVIEWERS
        assert "review-docs" in VALID_REVIEWERS

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
    def test_cost_limit_cancels_remaining_reviewers(self, mock_prompt, mock_agent) -> None:
        call_count = 0

        async def mock_run(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                return AgentResult(text="ok", session_id="s1")
            raise CostLimitError("cost exceeded on second reviewer")

        mock_agent.side_effect = mock_run

        with pytest.raises(CostLimitError):
            asyncio.run(run_parallel_reviewers(
                ["review-correctness", "review-security", "review-architecture"],
                pr_number=1,
                round_number=1,
                cwd="/tmp",
            ))

        # First reviewer should have succeeded before the limit was hit
        # The exact number of calls depends on asyncio task scheduling,
        # but at least 2 should have been attempted (one success, one failure)
        assert call_count >= 2

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
