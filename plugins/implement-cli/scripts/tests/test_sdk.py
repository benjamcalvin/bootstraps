"""Tests for implement_cli.sdk."""

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

from implement_cli.sdk import DEFAULT_TOOLS, AgentResult, run_agent
from implement_cli.tracking import CostLimitError, RecursionLimitError, RunContext
from implement_cli.types import Phase


class TestDefaultTools:
    def test_plan_tools(self) -> None:
        tools = DEFAULT_TOOLS[Phase.PLAN]
        assert "Read" in tools
        assert "Glob" in tools
        assert "Grep" in tools
        assert "Write" not in tools
        assert "Edit" not in tools

    def test_implement_tools(self) -> None:
        tools = DEFAULT_TOOLS[Phase.IMPLEMENT]
        assert "Read" in tools
        assert "Write" in tools
        assert "Edit" in tools
        assert "Bash" in tools

    def test_review_tools(self) -> None:
        tools = DEFAULT_TOOLS[Phase.REVIEW]
        assert "Read" in tools
        assert "Write" not in tools
        assert "Edit" not in tools

    def test_address_tools(self) -> None:
        tools = DEFAULT_TOOLS[Phase.ADDRESS]
        assert "Read" in tools
        assert "Write" in tools
        assert "Edit" in tools

    def test_all_phases_have_tools(self) -> None:
        for phase in Phase:
            assert phase in DEFAULT_TOOLS, f"Phase {phase} missing from DEFAULT_TOOLS"


class TestAgentResult:
    def test_creation(self) -> None:
        result = AgentResult(
            text="output text",
            session_id="sess-123",
            cost_usd=0.05,
            is_error=False,
        )
        assert result.text == "output text"
        assert result.session_id == "sess-123"
        assert result.cost_usd == 0.05
        assert result.is_error is False

    def test_defaults(self) -> None:
        result = AgentResult(text="test", session_id="s1")
        assert result.cost_usd is None
        assert result.is_error is False
        assert result.input_tokens == 0
        assert result.output_tokens == 0
        assert result.duration_ms == 0

    def test_repr(self) -> None:
        result = AgentResult(text="short", session_id="s1")
        r = repr(result)
        assert "s1" in r
        assert "short" in r

    def test_error_result(self) -> None:
        result = AgentResult(
            text="Something failed",
            session_id="s2",
            is_error=True,
        )
        assert result.is_error is True

    def test_to_dict(self) -> None:
        result = AgentResult(
            text="output",
            session_id="s1",
            cost_usd=0.5,
            input_tokens=1000,
            output_tokens=500,
            duration_ms=5000,
        )
        d = result.to_dict()
        assert d["session_id"] == "s1"
        assert d["cost_usd"] == 0.5
        assert d["input_tokens"] == 1000
        assert d["output_tokens"] == 500
        assert d["duration_ms"] == 5000
        assert d["text"] == "output"

    def test_to_dict_with_tokens(self) -> None:
        result = AgentResult(
            text="test",
            session_id="s1",
            input_tokens=2000,
            output_tokens=1000,
        )
        d = result.to_dict()
        assert d["input_tokens"] == 2000
        assert d["output_tokens"] == 1000

    def test_to_dict_includes_is_error(self) -> None:
        result = AgentResult(text="err", session_id="s1", is_error=True)
        d = result.to_dict()
        assert d["is_error"] is True


def _make_result_message(session_id="sess-1", cost=0.5, is_error=False):
    """Create a mock ResultMessage for testing."""
    from claude_agent_sdk import ResultMessage
    msg = MagicMock(spec=ResultMessage)
    msg.session_id = session_id
    msg.total_cost_usd = cost
    msg.duration_ms = 1000
    msg.is_error = is_error
    msg.usage = {"input_tokens": 100, "output_tokens": 50}
    msg.result = "final result"
    return msg


def _make_assistant_message(text="assistant text"):
    """Create a mock AssistantMessage for testing."""
    from claude_agent_sdk import AssistantMessage, TextBlock
    block = MagicMock(spec=TextBlock)
    block.text = text
    msg = MagicMock(spec=AssistantMessage)
    msg.content = [block]
    return msg


class TestRunAgent:
    @patch("implement_cli.sdk.query")
    def test_basic_invocation(self, mock_query) -> None:
        result_msg = _make_result_message()

        async def mock_stream(*args, **kwargs):
            yield _make_assistant_message("hello")
            yield result_msg

        mock_query.return_value = mock_stream()

        result = asyncio.run(run_agent(
            "test prompt",
            phase=Phase.REVIEW,
            role="test-role",
            cwd="/tmp",
        ))
        assert result.session_id == "sess-1"
        assert result.cost_usd == 0.5
        assert "hello" in result.text
        assert result.is_error is False

    @patch("implement_cli.sdk.query")
    def test_depth_tracking(self, mock_query) -> None:
        result_msg = _make_result_message()

        async def mock_stream(*args, **kwargs):
            yield result_msg

        mock_query.return_value = mock_stream()

        ctx = RunContext(max_depth=5)
        assert ctx.current_depth == 0

        asyncio.run(run_agent(
            "test",
            phase=Phase.REVIEW,
            role="test",
            cwd="/tmp",
            run_context=ctx,
        ))
        # Depth should return to 0 after run_agent completes
        assert ctx.current_depth == 0
        # Session was recorded at depth 1 (during the call)
        assert len(ctx.sessions) == 1
        assert ctx.sessions[0].depth == 1

    @patch("implement_cli.sdk.query")
    def test_session_recorded(self, mock_query) -> None:
        result_msg = _make_result_message(session_id="recorded-sess")

        async def mock_stream(*args, **kwargs):
            yield result_msg

        mock_query.return_value = mock_stream()

        ctx = RunContext(max_depth=5)
        asyncio.run(run_agent(
            "test",
            phase=Phase.REVIEW,
            role="test-reviewer",
            cwd="/tmp",
            run_context=ctx,
        ))
        assert len(ctx.sessions) == 1
        assert ctx.sessions[0].session_id == "recorded-sess"
        assert ctx.sessions[0].role == "test-reviewer"
        assert ctx.sessions[0].cost_usd == 0.5
        assert ctx.sessions[0].input_tokens == 100
        assert ctx.sessions[0].output_tokens == 50

    @patch("implement_cli.sdk.query")
    def test_context_files_appended(self, mock_query) -> None:
        result_msg = _make_result_message()

        async def mock_stream(*args, **kwargs):
            yield result_msg

        mock_query.return_value = mock_stream()

        asyncio.run(run_agent(
            "base prompt",
            phase=Phase.REVIEW,
            role="test",
            cwd="/tmp",
            context_files=["/tmp/a.md", "/tmp/b.md"],
        ))

        call_kwargs = mock_query.call_args
        prompt = call_kwargs.kwargs.get("prompt", call_kwargs.args[0] if call_kwargs.args else "")
        assert "/tmp/a.md" in prompt
        assert "/tmp/b.md" in prompt

    @patch("implement_cli.sdk.query")
    def test_depth_limit_raises(self, mock_query) -> None:
        ctx = RunContext(max_depth=1)
        ctx.current_depth = 1  # Already at limit

        import pytest
        with pytest.raises(RecursionLimitError):
            asyncio.run(run_agent(
                "test",
                phase=Phase.REVIEW,
                role="test",
                cwd="/tmp",
                run_context=ctx,
            ))
