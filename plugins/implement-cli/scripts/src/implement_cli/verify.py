"""Verification phase using claude-agent-sdk."""

from __future__ import annotations

import logging
from pathlib import Path

from implement_cli.prompts import load_prompt
from implement_cli.sdk import AgentResult, run_agent
from implement_cli.tracking import RunContext
from implement_cli.types import Phase

logger = logging.getLogger(__name__)


async def run_verifier(
    *,
    pr_number: int,
    cwd: str | Path,
    run_context: RunContext | None = None,
) -> AgentResult:
    """Run the verification agent to test the PR end-to-end.

    Args:
        pr_number: The PR number to verify.
        cwd: Working directory.
        run_context: Optional RunContext for tracking.

    Returns:
        The AgentResult containing verification verdict and evidence.
    """
    prompt = load_prompt("verify", PR_NUMBER=str(pr_number))

    logger.info("Starting verifier for PR #%d", pr_number)

    result = await run_agent(
        prompt,
        phase=Phase.VERIFY,
        role="verifier",
        cwd=cwd,
        run_context=run_context,
    )

    logger.info(
        "Verifier completed (session=%s, cost=$%.4f, error=%s)",
        result.session_id,
        result.cost_usd or 0,
        result.is_error,
    )
    return result
