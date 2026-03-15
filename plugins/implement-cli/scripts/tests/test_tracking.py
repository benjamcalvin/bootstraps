"""Tests for implement_cli.tracking."""

import json

import pytest

from implement_cli.tracking import (
    CostLimitError,
    RecursionLimitError,
    RunContext,
    SessionRecord,
    create_run_dir,
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


class TestRunDir:
    def test_create_run_dir_unique(self) -> None:
        dir1 = create_run_dir()
        dir2 = create_run_dir()
        assert dir1 != dir2
        assert dir1.exists()
        assert dir2.exists()

    def test_create_run_dir_prefix(self) -> None:
        d = create_run_dir(prefix="test-prefix")
        assert "test-prefix" in d.name

    def test_run_context_has_run_dir(self) -> None:
        ctx = RunContext()
        assert ctx.run_dir.exists()
        assert ctx.run_dir.is_dir()

    def test_artifact_path(self) -> None:
        ctx = RunContext()
        path = ctx.artifact_path("findings-round-1.md")
        assert path.parent == ctx.run_dir
        assert path.name == "findings-round-1.md"

    def test_artifact_path_no_collision(self) -> None:
        ctx1 = RunContext()
        ctx2 = RunContext()
        p1 = ctx1.artifact_path("findings.md")
        p2 = ctx2.artifact_path("findings.md")
        assert p1 != p2

    def test_summary_includes_run_dir(self) -> None:
        ctx = RunContext()
        summary = ctx.summary()
        assert "run_dir" in summary
        assert summary["run_dir"] == str(ctx.run_dir)

    def test_save_defaults_to_run_dir(self) -> None:
        ctx = RunContext()
        ctx.record_session(SessionRecord(
            session_id="s1",
            phase="review",
            role="reviewer",
            cost_usd=0.1,
        ))
        saved_path = ctx.save()
        assert saved_path == ctx.run_dir / "run_context.json"
        assert saved_path.exists()
        data = json.loads(saved_path.read_text())
        assert data["total_sessions"] == 1


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
