"""Tests for implement_cli.sdk."""

from implement_cli.sdk import DEFAULT_TOOLS, AgentResult
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
