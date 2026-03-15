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


class TestDryRun:
    """Tests for --dry-run flag behaviour."""

    def test_run_agent_dry_run(self, capsys) -> None:
        """Verify dry-run prints config and prompt without spawning agents."""
        main(["--dry-run", "run-agent", "--phase", "implement", "--role", "implementer", "Do the thing"])
        captured = capsys.readouterr()
        output = captured.out

        assert "=== DRY RUN: run-agent ===" in output
        assert "Phase: implement" in output
        assert "Role: implementer" in output
        assert "Model: (default)" in output
        # Check tools from DEFAULT_TOOLS for implement phase
        assert "Read" in output
        assert "Write" in output
        assert "Edit" in output
        assert "--- Prompt ---" in output
        assert "Do the thing" in output
        # Should NOT contain JSON tracking output (no agents ran)
        assert '"tracking"' not in output

    def test_run_reviewers_dry_run(self, capsys, tmp_path, monkeypatch) -> None:
        """Verify dry-run prints each reviewer's config without spawning agents."""
        # Create fake prompt templates for reviewers
        prompts_dir = tmp_path / "prompts"
        prompts_dir.mkdir()
        for reviewer in ("review-correctness", "review-security", "review-architecture", "review-testing"):
            (prompts_dir / f"{reviewer}.md").write_text(
                f"Review PR #$PR_NUMBER (round $ROUND_NUMBER) as {reviewer}"
            )
        monkeypatch.setattr("implement_cli.prompts.PROMPTS_DIR", prompts_dir)

        main(["--dry-run", "run-reviewers", "--pr", "45", "--round", "2"])
        captured = capsys.readouterr()
        output = captured.out

        assert "=== DRY RUN: run-reviewers ===" in output
        assert "PR: #45" in output
        assert "Round: 2" in output
        assert "--- Reviewer: review-correctness ---" in output
        assert "Review PR #45 (round 2) as review-correctness" in output
        assert "--- Reviewer: review-security ---" in output
        # Should NOT contain JSON tracking output
        assert '"tracking"' not in output

    def test_run_agent_dry_run_with_session_and_context_files(self, capsys) -> None:
        """Verify dry-run prints session-id and context-files when provided."""
        main([
            "--dry-run", "run-agent",
            "--session-id", "sess-abc123",
            "Do the thing",
            "--context-files", "foo.py", "bar.py",
        ])
        captured = capsys.readouterr()
        output = captured.out
        assert "Session ID: sess-abc123" in output
        assert "Context Files: foo.py, bar.py" in output

    def test_dry_run_unsupported_command(self, capsys) -> None:
        """Verify --dry-run with unsupported command prints error and exits 1."""
        with pytest.raises(SystemExit) as exc_info:
            main(["--dry-run", "debug", "sessions", "file.json"])
        assert exc_info.value.code == 1
        captured = capsys.readouterr()
        assert "--dry-run is not supported for 'debug'" in captured.err

    def test_dry_run_reviewers_invalid_reviewer(self, capsys) -> None:
        """Verify --dry-run run-reviewers rejects invalid reviewer names."""
        with pytest.raises(SystemExit) as exc_info:
            main(["--dry-run", "run-reviewers", "--pr", "10", "--reviewers", "review-bogus"])
        assert exc_info.value.code == 1
        captured = capsys.readouterr()
        assert "Unknown reviewer" in captured.err

    def test_dry_run_does_not_create_run_context(self, capsys) -> None:
        """Verify no tracking output — no agents ran."""
        main(["--dry-run", "run-agent", "Hello world"])
        captured = capsys.readouterr()
        # No JSON output at all — dry-run returns before the tracking epilogue
        assert '"tracking"' not in captured.out
        assert '"success"' not in captured.out


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
