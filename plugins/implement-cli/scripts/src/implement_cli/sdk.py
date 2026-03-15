"""Thin wrapper around claude-agent-sdk for subprocess invocation."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ResultMessage,
    TextBlock,
    query,
)

from implement_cli.types import Phase

logger = logging.getLogger(__name__)


DEFAULT_TOOLS: dict[Phase, list[str]] = {
    Phase.PLAN: ["Read", "Glob", "Grep", "Bash"],
    Phase.IMPLEMENT: ["Read", "Write", "Edit", "Glob", "Grep", "Bash"],
    Phase.REVIEW: ["Read", "Glob", "Grep", "Bash"],
    Phase.ADDRESS: ["Read", "Write", "Edit", "Glob", "Grep", "Bash"],
    Phase.DOCS: ["Read", "Glob", "Grep", "Bash"],
    Phase.VERIFY: ["Read", "Glob", "Grep", "Bash"],
    Phase.MERGE: ["Read", "Glob", "Grep", "Bash"],
}


async def run_agent(
    prompt: str,
    *,
    phase: Phase,
    cwd: str | Path,
    session_id: str | None = None,
    model: str | None = None,
    allowed_tools: list[str] | None = None,
    permission_mode: str = "bypassPermissions",
) -> AgentResult:
    """Run a claude-agent-sdk subprocess and collect the result.

    Args:
        prompt: The prompt to send to the agent.
        phase: The lifecycle phase (determines default tools).
        cwd: Working directory for the agent.
        session_id: Optional session ID to resume.
        model: Optional model override.
        allowed_tools: Override the default tool set for this phase.
        permission_mode: Permission mode for the agent.

    Returns:
        An AgentResult with the text output and session ID.
    """
    tools = allowed_tools or DEFAULT_TOOLS.get(phase, [])

    options = ClaudeAgentOptions(
        allowed_tools=tools,
        cwd=str(cwd),
        permission_mode=permission_mode,
    )

    if session_id:
        options.resume = session_id
    if model:
        options.model = model

    text_parts: list[str] = []
    result_session_id: str | None = None
    cost_usd: float | None = None
    is_error = False

    async for message in query(prompt=prompt, options=options):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    text_parts.append(block.text)
        elif isinstance(message, ResultMessage):
            result_session_id = message.session_id
            cost_usd = message.total_cost_usd
            is_error = message.is_error
            if message.result:
                text_parts.append(message.result)

    text = "\n".join(text_parts)

    if is_error:
        logger.error("Agent returned error for phase %s: %s", phase.value, text[:500])

    return AgentResult(
        text=text,
        session_id=result_session_id or "",
        cost_usd=cost_usd,
        is_error=is_error,
    )


class AgentResult:
    """Result from a claude-agent-sdk agent invocation."""

    __slots__ = ("text", "session_id", "cost_usd", "is_error")

    def __init__(
        self,
        text: str,
        session_id: str,
        cost_usd: float | None = None,
        is_error: bool = False,
    ) -> None:
        self.text = text
        self.session_id = session_id
        self.cost_usd = cost_usd
        self.is_error = is_error

    def __repr__(self) -> str:
        return (
            f"AgentResult(session_id={self.session_id!r}, "
            f"is_error={self.is_error}, "
            f"cost_usd={self.cost_usd}, "
            f"text={self.text[:80]!r}...)"
        )
