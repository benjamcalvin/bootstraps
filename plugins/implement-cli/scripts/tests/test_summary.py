"""Tests for implement_cli.summary and the CLI summary subcommand."""

import json

import pytest

from implement_cli.cli import main
from implement_cli.summary import format_summary


def _make_run_context(sessions, **overrides):
    """Build a minimal run_context dict with given sessions."""
    total_cost = sum(s.get("cost_usd") or 0 for s in sessions)
    total_in = sum(s.get("input_tokens", 0) for s in sessions)
    total_out = sum(s.get("output_tokens", 0) for s in sessions)
    data = {
        "run_dir": "/tmp/implement-cli-test",
        "total_cost_usd": total_cost,
        "total_input_tokens": total_in,
        "total_output_tokens": total_out,
        "total_sessions": len(sessions),
        "max_depth_reached": 1,
        "elapsed_seconds": 100.0,
        "sessions": sessions,
    }
    data.update(overrides)
    return data


def _session(phase, role, cost=0.5, duration_ms=5000, is_error=False,
             input_tokens=1000, output_tokens=500):
    return {
        "session_id": f"{phase}-{role}",
        "phase": phase,
        "role": role,
        "cost_usd": cost,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "duration_ms": duration_ms,
        "is_error": is_error,
        "depth": 1,
    }


class TestFormatSummary:
    def test_multi_phase(self):
        data = _make_run_context([
            _session("plan", "planner", cost=0.42, duration_ms=32000),
            _session("implement", "implementer", cost=1.89, duration_ms=94000),
            _session("review", "review-correctness", cost=0.45, duration_ms=11000),
            _session("review", "review-security", cost=0.45, duration_ms=11000),
            _session("review", "review-architecture", cost=0.45, duration_ms=11000),
            _session("review", "review-testing", cost=0.45, duration_ms=12000),
            _session("verify", "verifier", cost=0.52, duration_ms=28000),
            _session("merge", "merger", cost=0.15, duration_ms=8000),
        ])
        result = format_summary(data)

        assert "Run Summary:" in result
        assert "plan" in result
        assert "implement" in result
        assert "review" in result
        assert "verify" in result
        assert "merge" in result
        assert "ALL PHASES PASSED" in result
        # Review sessions should be aggregated
        assert result.count("review") >= 1

    def test_single_session(self):
        data = _make_run_context([
            _session("implement", "implementer", cost=1.0, duration_ms=60000),
        ])
        result = format_summary(data)

        assert "implement" in result
        assert "PASS" in result
        assert "$1.00" in result
        assert "60s" in result
        assert "ALL PHASES PASSED" in result

    def test_session_with_error(self):
        data = _make_run_context([
            _session("plan", "planner", cost=0.5, duration_ms=10000),
            _session("implement", "implementer", cost=1.0, duration_ms=30000, is_error=True),
        ])
        result = format_summary(data)

        assert "FAIL" in result
        assert "FAILED" in result
        assert "implement" in result

    def test_phase_aggregation(self):
        data = _make_run_context([
            _session("review", "review-correctness", cost=0.45, duration_ms=11000),
            _session("review", "review-security", cost=0.35, duration_ms=9000),
            _session("review", "review-architecture", cost=0.40, duration_ms=10000),
        ])
        result = format_summary(data)

        # Should show aggregated cost for review phase
        assert "$1.20" in result
        # Should show aggregated duration (11+9+10 = 30s)
        assert "30s" in result
        # Should show session count of 3
        lines = result.split("\n")
        review_line = [l for l in lines if l.startswith("review")][0]
        assert "3" in review_line

    def test_token_summary(self):
        data = _make_run_context(
            [_session("plan", "planner", input_tokens=150000, output_tokens=25000)],
            total_input_tokens=150000,
            total_output_tokens=25000,
        )
        result = format_summary(data)

        assert "150,000 in" in result
        assert "25,000 out" in result

    def test_failed_phases_listed(self):
        data = _make_run_context([
            _session("plan", "planner"),
            _session("implement", "implementer", is_error=True),
            _session("verify", "verifier", is_error=True),
        ])
        result = format_summary(data)

        assert "FAILED" in result
        assert "implement" in result
        assert "verify" in result

    def test_empty_sessions(self):
        data = _make_run_context([])
        result = format_summary(data)

        assert "Run Summary:" in result
        assert "Total" in result
        assert "ALL PHASES PASSED" in result

    def test_phase_ordering(self):
        """Phases should appear in canonical order regardless of input order."""
        data = _make_run_context([
            _session("merge", "merger"),
            _session("plan", "planner"),
            _session("implement", "implementer"),
        ])
        result = format_summary(data)
        lines = result.split("\n")

        phase_lines = [l for l in lines if any(
            l.startswith(p) for p in ["plan", "implement", "merge"]
        )]
        assert len(phase_lines) == 3
        assert phase_lines[0].startswith("plan")
        assert phase_lines[1].startswith("implement")
        assert phase_lines[2].startswith("merge")


class TestSummarySubcommand:
    def test_help_includes_summary(self, capsys):
        with pytest.raises(SystemExit) as exc_info:
            main(["summary", "--help"])
        assert exc_info.value.code == 0
        captured = capsys.readouterr()
        assert "run_context_file" in captured.out

    def test_missing_file(self, tmp_path, capsys):
        with pytest.raises(SystemExit) as exc_info:
            main(["summary", str(tmp_path / "nonexistent.json")])
        assert exc_info.value.code == 1
        captured = capsys.readouterr()
        assert "not found" in captured.err.lower()

    def test_invalid_json(self, tmp_path, capsys):
        bad_file = tmp_path / "bad.json"
        bad_file.write_text("not valid json {{{")
        with pytest.raises(SystemExit) as exc_info:
            main(["summary", str(bad_file)])
        assert exc_info.value.code == 1
        captured = capsys.readouterr()
        assert "invalid json" in captured.err.lower()

    def test_valid_file(self, tmp_path, capsys):
        ctx_file = tmp_path / "run_context.json"
        data = _make_run_context([
            _session("plan", "planner", cost=0.42, duration_ms=32000),
            _session("implement", "implementer", cost=1.89, duration_ms=94000),
        ])
        ctx_file.write_text(json.dumps(data))

        main(["summary", str(ctx_file)])
        captured = capsys.readouterr()

        assert "Run Summary:" in captured.out
        assert "plan" in captured.out
        assert "implement" in captured.out
        assert "ALL PHASES PASSED" in captured.out
