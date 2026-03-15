"""Thin wrapper around claude-agent-sdk for subprocess invocation."""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from pathlib import Path

from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ResultMessage,
    TextBlock,
    query,
)

from implement_cli.tracking import RunContext, SessionRecord
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
    role: str,
    cwd: str | Path,
    run_context: RunContext | None = None,
    session_id: str | None = None,
    model: str | None = None,
    allowed_tools: list[str] | None = None,
    permission_mode: str = "bypassPermissions",
    context_files: list[str | Path] | None = None,
) -> AgentResult:
    """Run a claude-agent-sdk subprocess and collect the result.

    Args:
        prompt: The prompt to send to the agent.
        phase: The lifecycle phase (determines default tools).
        role: Human-readable role label (e.g., "review-correctness").
        cwd: Working directory for the agent.
        run_context: Optional RunContext for tracking costs and enforcing limits.
        session_id: Optional session ID to resume.
        model: Optional model override.
        allowed_tools: Override the default tool set for this phase.
        permission_mode: Permission mode for the agent.
        context_files: Paths to files the agent should read. Appended to the
            prompt as "Read the following files for context: ..." so the agent
            uses its own Read tool rather than bloating the prompt.

    Returns:
        An AgentResult with the text output, session ID, and tracking metadata.
    """
    # Enforce limits before starting
    if run_context:
        run_context.check_cost()
        run_context.enter_depth()  # enter_depth() calls check_depth() internally

    try:
        return await _run_agent_inner(
            prompt,
            phase=phase,
            role=role,
            cwd=cwd,
            run_context=run_context,
            session_id=session_id,
            model=model,
            allowed_tools=allowed_tools,
            permission_mode=permission_mode,
            context_files=context_files,
        )
    finally:
        if run_context:
            run_context.exit_depth()


async def _run_agent_inner(
    prompt: str,
    *,
    phase: Phase,
    role: str,
    cwd: str | Path,
    run_context: RunContext | None,
    session_id: str | None,
    model: str | None,
    allowed_tools: list[str] | None,
    permission_mode: str,
    context_files: list[str | Path] | None,
) -> AgentResult:
    """Inner implementation of run_agent (separated for depth tracking)."""
    tools = allowed_tools or DEFAULT_TOOLS.get(phase, [])

    # Append context file references to prompt
    effective_prompt = prompt
    if context_files:
        file_list = "\n".join(f"- `{p}`" for p in context_files)
        effective_prompt += (
            f"\n\n## Context Files\n\n"
            f"Read the following files for additional context:\n{file_list}"
        )

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
    input_tokens: int = 0
    output_tokens: int = 0
    duration_ms: int = 0
    is_error = False

    async for message in query(prompt=effective_prompt, options=options):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    text_parts.append(block.text)
        elif isinstance(message, ResultMessage):
            result_session_id = message.session_id
            cost_usd = message.total_cost_usd
            duration_ms = message.duration_ms
            is_error = message.is_error
            if message.usage:
                input_tokens = message.usage.get("input_tokens", 0)
                output_tokens = message.usage.get("output_tokens", 0)
            if message.result:
                text_parts.append(message.result)

    text = "\n".join(text_parts)

    if is_error:
        logger.error("Agent returned error for %s/%s: %s", phase.value, role, text[:500])

    # Record in run context
    if run_context and result_session_id:
        run_context.record_session(
            SessionRecord(
                session_id=result_session_id,
                phase=phase.value,
                role=role,
                cost_usd=cost_usd,
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                duration_ms=duration_ms,
                is_error=is_error,
            )
        )

    return AgentResult(
        text=text,
        session_id=result_session_id or "",
        cost_usd=cost_usd,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        duration_ms=duration_ms,
        is_error=is_error,
    )


@dataclass
class AgentResult:
    """Result from a claude-agent-sdk agent invocation."""

    text: str
    session_id: str
    cost_usd: float | None = None
    input_tokens: int = 0
    output_tokens: int = 0
    duration_ms: int = 0
    is_error: bool = False

    def to_dict(self) -> dict:
        """Serialize to a dict for JSON output."""
        return {
            "session_id": self.session_id,
            "cost_usd": self.cost_usd,
            "input_tokens": self.input_tokens,
            "output_tokens": self.output_tokens,
            "duration_ms": self.duration_ms,
            "is_error": self.is_error,
            "text": self.text,
        }

    def __repr__(self) -> str:
        return (
            f"AgentResult(session_id={self.session_id!r}, "
            f"is_error={self.is_error}, "
            f"cost=${self.cost_usd or 0:.4f}, "
            f"tokens={self.input_tokens}/{self.output_tokens}, "
            f"text={self.text[:80]!r}...)"
        )
