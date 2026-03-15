"""Merge phase using claude-agent-sdk."""

from __future__ import annotations

import logging
from pathlib import Path

from implement_cli.prompts import load_prompt
from implement_cli.sdk import AgentResult, run_agent
from implement_cli.types import Phase

logger = logging.getLogger(__name__)


async def run_merger(
    *,
    pr_number: int,
    cwd: str | Path,
) -> AgentResult:
    """Run the merge agent to squash-merge the PR.

    Args:
        pr_number: The PR number to merge.
        cwd: Working directory.

    Returns:
        The AgentResult containing merge status and issue updates.
    """
    prompt = load_prompt("merge", PR_NUMBER=str(pr_number))

    logger.info("Starting merger for PR #%d", pr_number)

    result = await run_agent(
        prompt,
        phase=Phase.MERGE,
        cwd=cwd,
    )

    logger.info(
        "Merger completed (session=%s, error=%s)",
        result.session_id,
        result.is_error,
    )
    return result
