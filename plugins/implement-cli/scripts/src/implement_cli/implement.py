"""Implementation phase using claude-agent-sdk."""

from __future__ import annotations

import logging
from pathlib import Path

from implement_cli.prompts import load_prompt
from implement_cli.sdk import AgentResult, run_agent
from implement_cli.types import Phase

logger = logging.getLogger(__name__)


async def run_implementer(
    *,
    task_description: str,
    plan: str | None = None,
    issue_number: int | None = None,
    skip_planning: bool = False,
    cwd: str | Path,
) -> AgentResult:
    """Run the implementer agent to write code, tests, and create a PR.

    Args:
        task_description: Full task description with acceptance criteria.
        plan: Optional pre-computed plan from the planning phase.
        issue_number: Optional linked issue number.
        skip_planning: Whether to skip the internal planning step.
        cwd: Working directory.

    Returns:
        The AgentResult containing PR number and summary.
    """
    variables: dict[str, str] = {
        "TASK_DESCRIPTION": task_description,
        "ISSUE_NUMBER": str(issue_number or 0),
    }

    if plan:
        variables["PLAN"] = plan
    if skip_planning:
        variables["SKIP_PLANNING"] = "true"

    prompt = load_prompt("implement", **variables)

    logger.info("Starting implementer (issue=%s, skip_planning=%s)", issue_number, skip_planning)

    result = await run_agent(
        prompt,
        phase=Phase.IMPLEMENT,
        cwd=cwd,
    )

    logger.info(
        "Implementer completed (session=%s, error=%s)",
        result.session_id,
        result.is_error,
    )
    return result
