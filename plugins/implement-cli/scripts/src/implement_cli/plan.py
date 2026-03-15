"""Planning phase using claude-agent-sdk."""

from __future__ import annotations

import logging
from pathlib import Path

from implement_cli.prompts import load_prompt
from implement_cli.sdk import AgentResult, run_agent
from implement_cli.tracking import RunContext
from implement_cli.types import Phase

logger = logging.getLogger(__name__)


async def run_planner(
    *,
    task_description: str,
    cwd: str | Path,
    run_context: RunContext | None = None,
) -> AgentResult:
    """Run the planning agent to explore and plan implementation.

    Args:
        task_description: Full task description with acceptance criteria.
        cwd: Working directory.
        run_context: Optional RunContext for tracking.

    Returns:
        The AgentResult containing the implementation plan.
    """
    prompt = load_prompt("plan", TASK_DESCRIPTION=task_description)

    logger.info("Starting planner")

    result = await run_agent(
        prompt,
        phase=Phase.PLAN,
        role="planner",
        cwd=cwd,
        run_context=run_context,
    )

    logger.info(
        "Planner completed (session=%s, cost=$%.4f, error=%s)",
        result.session_id,
        result.cost_usd or 0,
        result.is_error,
    )
    return result
