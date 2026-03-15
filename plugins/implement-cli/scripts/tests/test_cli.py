"""Tests for implement_cli.cli."""

import json

import pytest

from implement_cli.cli import main


class TestCliHelp:
    def test_help_exits(self) -> None:
        with pytest.raises(SystemExit) as exc_info:
            main(["--help"])
        assert exc_info.value.code == 0

    def test_run_agent_help(self) -> None:
        with pytest.raises(SystemExit) as exc_info:
            main(["run-agent", "--help"])
        assert exc_info.value.code == 0

    def test_run_reviewers_help(self) -> None:
        with pytest.raises(SystemExit) as exc_info:
            main(["run-reviewers", "--help"])
        assert exc_info.value.code == 0

    def test_debug_help(self) -> None:
        with pytest.raises(SystemExit) as exc_info:
            main(["debug", "--help"])
        assert exc_info.value.code == 0

    def test_no_command_exits(self) -> None:
        with pytest.raises(SystemExit) as exc_info:
            main([])
        assert exc_info.value.code != 0


class TestDebugSessions:
    def test_missing_file(self, tmp_path, capsys) -> None:
        main(["debug", "sessions", str(tmp_path / "nonexistent.json")])
        captured = capsys.readouterr()
        output = json.loads(captured.out)
        assert "error" in output
        assert "not found" in output["error"].lower()

    def test_valid_file(self, tmp_path, capsys) -> None:
        ctx_file = tmp_path / "run.json"
        ctx_file.write_text(json.dumps({
            "total_cost_usd": 1.23,
            "total_sessions": 3,
            "elapsed_seconds": 60.0,
            "sessions": [
                {
                    "session_id": "s1",
                    "phase": "review",
                    "role": "review-correctness",
                    "cost_usd": 0.5,
                    "is_error": False,
                    "depth": 1,
                    "input_tokens": 1000,
                    "output_tokens": 500,
                    "duration_ms": 5000,
                },
            ],
        }))
        main(["debug", "sessions", str(ctx_file)])
        captured = capsys.readouterr()
        output = json.loads(captured.out)
        assert output["success"] is True
        assert output["total_cost_usd"] == 1.23
        assert len(output["sessions"]) == 1
        assert output["sessions"][0]["session_id"] == "s1"
