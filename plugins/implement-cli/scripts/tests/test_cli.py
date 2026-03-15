"""Tests for implement_cli.cli."""

import argparse
import json

import pytest

from implement_cli.cli import _resolve_prompt, main


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


class TestResolvePrompt:
    def test_prompt_from_argument(self) -> None:
        args = argparse.Namespace(prompt="hello world", prompt_file=None)
        assert _resolve_prompt(args) == "hello world"

    def test_prompt_from_file(self, tmp_path) -> None:
        prompt_file = tmp_path / "prompt.md"
        prompt_file.write_text("file prompt content")
        args = argparse.Namespace(prompt=None, prompt_file=str(prompt_file))
        assert _resolve_prompt(args) == "file prompt content"

    def test_prompt_argument_takes_precedence(self, tmp_path) -> None:
        prompt_file = tmp_path / "prompt.md"
        prompt_file.write_text("from file")
        args = argparse.Namespace(prompt="from arg", prompt_file=str(prompt_file))
        assert _resolve_prompt(args) == "from arg"

    def test_missing_prompt_exits(self, monkeypatch) -> None:
        monkeypatch.setattr("sys.stdin", type("FakeTTY", (), {"isatty": lambda self: True})())
        args = argparse.Namespace(prompt=None, prompt_file=None)
        with pytest.raises(SystemExit):
            _resolve_prompt(args)


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
