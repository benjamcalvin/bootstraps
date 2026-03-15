"""Tests for implement_cli.tracking."""

import json

import pytest

from implement_cli.tracking import (
    CostLimitError,
    RecursionLimitError,
    RunContext,
    SessionRecord,
)


class TestRunContext:
    def test_initial_state(self) -> None:
        ctx = RunContext()
        assert ctx.current_depth == 0
        assert ctx.total_cost_usd == 0.0
        assert ctx.total_input_tokens == 0
        assert ctx.total_output_tokens == 0
        assert ctx.sessions == []

    def test_enter_exit_depth(self) -> None:
        ctx = RunContext(max_depth=3)
        assert ctx.enter_depth() == 1
        assert ctx.enter_depth() == 2
        assert ctx.exit_depth() == 1
        assert ctx.exit_depth() == 0

    def test_depth_limit_enforced(self) -> None:
        ctx = RunContext(max_depth=2)
        ctx.enter_depth()
        ctx.enter_depth()
        with pytest.raises(RecursionLimitError, match="exceeds limit 2"):
            ctx.enter_depth()

    def test_exit_depth_floors_at_zero(self) -> None:
        ctx = RunContext()
        ctx.exit_depth()
        assert ctx.current_depth == 0

    def test_record_session(self) -> None:
        ctx = RunContext()
        record = SessionRecord(
            session_id="s1",
            phase="review",
            role="review-correctness",
            cost_usd=0.5,
            input_tokens=1000,
            output_tokens=500,
            duration_ms=5000,
        )
        ctx.record_session(record)

        assert len(ctx.sessions) == 1
        assert ctx.total_cost_usd == 0.5
        assert ctx.total_input_tokens == 1000
        assert ctx.total_output_tokens == 500

    def test_cumulative_cost(self) -> None:
        ctx = RunContext(max_cost_usd=100.0)
        for i in range(5):
            ctx.record_session(SessionRecord(
                session_id=f"s{i}",
                phase="review",
                role="reviewer",
                cost_usd=10.0,
            ))
        assert ctx.total_cost_usd == 50.0

    def test_cost_limit_enforced(self) -> None:
        ctx = RunContext(max_cost_usd=1.0)
        with pytest.raises(CostLimitError, match="exceeds limit"):
            ctx.record_session(SessionRecord(
                session_id="s1",
                phase="review",
                role="reviewer",
                cost_usd=1.5,
            ))

    def test_none_cost_ignored(self) -> None:
        ctx = RunContext()
        ctx.record_session(SessionRecord(
            session_id="s1",
            phase="review",
            role="reviewer",
            cost_usd=None,
        ))
        assert ctx.total_cost_usd == 0.0

    def test_summary(self) -> None:
        ctx = RunContext()
        ctx.record_session(SessionRecord(
            session_id="s1",
            phase="review",
            role="review-correctness",
            cost_usd=0.5,
            input_tokens=1000,
            output_tokens=500,
            duration_ms=5000,
        ))
        summary = ctx.summary()
        assert summary["total_cost_usd"] == 0.5
        assert summary["total_sessions"] == 1
        assert len(summary["sessions"]) == 1
        assert summary["sessions"][0]["session_id"] == "s1"

    def test_save(self, tmp_path) -> None:
        ctx = RunContext()
        ctx.record_session(SessionRecord(
            session_id="s1",
            phase="implement",
            role="implementer",
            cost_usd=2.0,
            input_tokens=5000,
            output_tokens=2000,
            duration_ms=10000,
        ))
        path = tmp_path / "run.json"
        ctx.save(path)

        data = json.loads(path.read_text())
        assert data["total_cost_usd"] == 2.0
        assert data["total_sessions"] == 1

    def test_check_depth_within_limit(self) -> None:
        ctx = RunContext(max_depth=5)
        ctx.current_depth = 4
        ctx.check_depth()  # Should not raise

    def test_check_cost_within_limit(self) -> None:
        ctx = RunContext(max_cost_usd=10.0)
        ctx.check_cost()  # Should not raise


class TestSessionRecord:
    def test_defaults(self) -> None:
        record = SessionRecord(
            session_id="s1",
            phase="review",
            role="reviewer",
        )
        assert record.cost_usd is None
        assert record.input_tokens == 0
        assert record.output_tokens == 0
        assert record.duration_ms == 0
        assert record.is_error is False
        assert record.depth == 0
        assert record.parent_session_id is None

    def test_error_record(self) -> None:
        record = SessionRecord(
            session_id="s1",
            phase="address",
            role="addresser",
            is_error=True,
        )
        assert record.is_error is True
