"""Parallel review runner using claude-agent-sdk."""

from __future__ import annotations

import asyncio
import logging
from pathlib import Path

from implement_cli.prompts import load_prompt
from implement_cli.sdk import AgentResult, run_agent
from implement_cli.tracking import RunContext
from implement_cli.types import Phase

logger = logging.getLogger(__name__)

REVIEWER_NAMES = [
    "review-correctness",
    "review-security",
    "review-architecture",
    "review-testing",
    "review-docs",
]


async def run_reviewer(
    reviewer: str,
    *,
    pr_number: int,
    round_number: int,
    cwd: str | Path,
    run_context: RunContext | None = None,
) -> AgentResult:
    """Run a single specialist reviewer.

    Args:
        reviewer: The reviewer name (e.g., "review-correctness").
        pr_number: The PR number to review.
        round_number: The current review round.
        cwd: Working directory.
        run_context: Optional RunContext for tracking.

    Returns:
        The AgentResult from the reviewer.
    """
    prompt = load_prompt(
        reviewer,
        PR_NUMBER=str(pr_number),
        ROUND_NUMBER=str(round_number),
    )
    logger.info("Starting %s for PR #%d, round %d", reviewer, pr_number, round_number)

    result = await run_agent(
        prompt,
        phase=Phase.REVIEW,
        role=reviewer,
        cwd=cwd,
        run_context=run_context,
    )

    logger.info(
        "%s completed (session=%s, cost=$%.4f, error=%s)",
        reviewer,
        result.session_id,
        result.cost_usd or 0,
        result.is_error,
    )
    return result


async def run_parallel_reviewers(
    reviewers: list[str],
    *,
    pr_number: int,
    round_number: int,
    cwd: str | Path,
    run_context: RunContext | None = None,
) -> dict[str, AgentResult]:
    """Run multiple specialist reviewers in parallel.

    Args:
        reviewers: List of reviewer names to invoke.
        pr_number: The PR number to review.
        round_number: The current review round.
        cwd: Working directory.
        run_context: Optional RunContext for tracking.

    Returns:
        A dict mapping reviewer name to AgentResult.
    """
    tasks = {
        reviewer: asyncio.create_task(
            run_reviewer(
                reviewer,
                pr_number=pr_number,
                round_number=round_number,
                cwd=cwd,
                run_context=run_context,
            )
        )
        for reviewer in reviewers
    }

    results: dict[str, AgentResult] = {}
    for reviewer, task in tasks.items():
        try:
            results[reviewer] = await task
        except Exception:
            logger.exception("Reviewer %s failed", reviewer)
            results[reviewer] = AgentResult(
                text=f"Reviewer {reviewer} failed with an exception.",
                session_id="",
                is_error=True,
            )

    return results
