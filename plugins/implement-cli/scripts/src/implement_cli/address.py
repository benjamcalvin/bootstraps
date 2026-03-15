"""Address review findings using claude-agent-sdk."""

from __future__ import annotations

import logging
from pathlib import Path

from implement_cli.prompts import load_prompt
from implement_cli.sdk import AgentResult, run_agent
from implement_cli.tracking import RunContext
from implement_cli.types import Phase

logger = logging.getLogger(__name__)


async def run_addresser(
    *,
    pr_number: int,
    round_number: int,
    findings_path: str | Path,
    cwd: str | Path,
    run_context: RunContext | None = None,
    session_id: str | None = None,
) -> AgentResult:
    """Run the addresser agent to fix review findings.

    Args:
        pr_number: The PR number.
        round_number: The current review round.
        findings_path: Path to the filtered findings file.
        cwd: Working directory.
        run_context: Optional RunContext for tracking.
        session_id: Optional session ID to resume a previous addresser session.

    Returns:
        The AgentResult from the addresser.
    """
    prompt = load_prompt(
        "address",
        PR_NUMBER=str(pr_number),
        ROUND_NUMBER=str(round_number),
        FINDINGS_PATH=str(findings_path),
    )

    logger.info(
        "Starting addresser for PR #%d, round %d, findings=%s",
        pr_number,
        round_number,
        findings_path,
    )

    result = await run_agent(
        prompt,
        phase=Phase.ADDRESS,
        role="addresser",
        cwd=cwd,
        run_context=run_context,
        session_id=session_id,
        context_files=[str(findings_path)],
    )

    logger.info(
        "Addresser completed (session=%s, cost=$%.4f, error=%s)",
        result.session_id,
        result.cost_usd or 0,
        result.is_error,
    )
    return result
