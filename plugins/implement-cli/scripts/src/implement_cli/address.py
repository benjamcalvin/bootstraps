"""Address review findings using claude-agent-sdk."""

from __future__ import annotations

import logging
from pathlib import Path

from implement_cli.prompts import load_prompt
from implement_cli.sdk import AgentResult, run_agent
from implement_cli.types import Phase

logger = logging.getLogger(__name__)


async def run_addresser(
    *,
    pr_number: int,
    round_number: int,
    findings_path: str | Path,
    cwd: str | Path,
    session_id: str | None = None,
) -> AgentResult:
    """Run the addresser agent to fix review findings.

    Args:
        pr_number: The PR number.
        round_number: The current review round.
        findings_path: Path to the filtered findings file.
        cwd: Working directory.
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
        cwd=cwd,
        session_id=session_id,
    )

    logger.info(
        "Addresser completed (session=%s, error=%s)",
        result.session_id,
        result.is_error,
    )
    return result
