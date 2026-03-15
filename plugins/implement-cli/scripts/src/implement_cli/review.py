"""Parallel review runner using claude-agent-sdk."""

from __future__ import annotations

import asyncio
import logging
from pathlib import Path

from implement_cli.prompts import load_prompt
from implement_cli.sdk import AgentResult, run_agent
from implement_cli.tracking import CostLimitError, RecursionLimitError, RunContext
from implement_cli.types import Phase, VALID_REVIEWERS

logger = logging.getLogger(__name__)


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
    if reviewer not in VALID_REVIEWERS:
        raise ValueError(
            f"Unknown reviewer {reviewer!r}. Valid reviewers: {VALID_REVIEWERS}"
        )

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
    cost_error: CostLimitError | None = None
    for reviewer, task in tasks.items():
        try:
            results[reviewer] = await task
        except (CostLimitError, RecursionLimitError) as e:
            logger.error("Reviewer %s hit limit: %s — cancelling remaining tasks", reviewer, e)
            # Cancel remaining tasks that haven't been awaited yet
            for other_reviewer, other_task in tasks.items():
                if other_reviewer not in results and other_reviewer != reviewer:
                    other_task.cancel()
            results[reviewer] = AgentResult(
                text=f"Reviewer {reviewer} hit limit: {e}",
                session_id="",
                is_error=True,
            )
            # Await cancelled tasks to suppress asyncio warnings
            cancelled = [
                t for r, t in tasks.items()
                if r not in results and r != reviewer
            ]
            if cancelled:
                await asyncio.gather(*cancelled, return_exceptions=True)
            if isinstance(e, CostLimitError):
                cost_error = e
            else:
                raise
            break
        except Exception:
            logger.exception("Reviewer %s failed", reviewer)
            results[reviewer] = AgentResult(
                text=f"Reviewer {reviewer} failed with an exception.",
                session_id="",
                is_error=True,
            )

    if cost_error is not None:
        raise cost_error

    return results
