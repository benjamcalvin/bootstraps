"""CLI entry point with subcommands.

Subcommands:
    run-agent      Run a single agent with a prompt (from arg, file, or stdin).
    run-reviewers  Run specialist reviewers in parallel for a PR.
    orchestrate    Run the full lifecycle orchestrator.
    summary        Print a human-readable summary of a completed run.
    debug          Inspect sessions from a previous run.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
from pathlib import Path

from implement_cli.tracking import CostLimitError, RecursionLimitError, RunContext

logger = logging.getLogger(__name__)


def _load_version() -> str:
    """Read the version string from plugin.json."""
    plugin_json = Path(__file__).resolve().parent.parent.parent.parent / ".claude-plugin" / "plugin.json"
    try:
        data = json.loads(plugin_json.read_text())
        return data["version"]
    except (FileNotFoundError, KeyError, json.JSONDecodeError):
        return "unknown"


def main(argv: list[str] | None = None) -> None:
    """Top-level CLI entry point."""
    # Handle --version before argparse so it works without a subcommand
    args_to_parse = argv if argv is not None else sys.argv[1:]
    if "--version" in args_to_parse:
        print(f"implement-cli {_load_version()}")
        sys.exit(0)

    parser = argparse.ArgumentParser(
        prog="implement-cli",
        description="CLI-based implementation lifecycle orchestrator",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose logging",
    )
    parser.add_argument(
        "--max-depth",
        type=int,
        default=5,
        help="Maximum recursion depth for agent invocations (default: 5)",
    )
    parser.add_argument(
        "--max-cost",
        type=float,
        default=50.0,
        help="Maximum cumulative cost in USD before aborting (default: 50.0)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print resolved configuration without running agents",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    # --- run-agent ---
    agent_parser = subparsers.add_parser(
        "run-agent",
        help="Run a single agent with a prompt",
    )
    agent_parser.add_argument(
        "prompt",
        nargs="?",
        default=None,
        help="Prompt text (omit to read from --prompt-file or stdin)",
    )
    agent_parser.add_argument(
        "--prompt-file",
        type=str,
        default=None,
        help="Read prompt from a file instead of argument",
    )
    agent_parser.add_argument(
        "--phase",
        default="implement",
        choices=["plan", "implement", "review", "address", "docs", "verify", "merge"],
        help="Phase (determines default tools). Default: implement",
    )
    agent_parser.add_argument(
        "--role",
        default="agent",
        help="Human-readable role label for tracking (default: agent)",
    )
    agent_parser.add_argument(
        "--cwd",
        default=".",
        help="Working directory for the agent (default: current directory)",
    )
    agent_parser.add_argument(
        "--session-id",
        default=None,
        help="Session ID to resume",
    )
    agent_parser.add_argument(
        "--model",
        default=None,
        help="Model override",
    )
    agent_parser.add_argument(
        "--tools",
        nargs="*",
        default=None,
        help="Override allowed tools (default: phase-based)",
    )
    agent_parser.add_argument(
        "--context-files",
        nargs="*",
        default=None,
        help="Files the agent should read for context",
    )

    # --- run-reviewers ---
    reviewers_parser = subparsers.add_parser(
        "run-reviewers",
        help="Run specialist reviewers in parallel for a PR",
    )
    reviewers_parser.add_argument(
        "--pr",
        type=int,
        required=True,
        help="PR number to review",
    )
    reviewers_parser.add_argument(
        "--round",
        type=int,
        default=1,
        help="Review round number (default: 1)",
    )
    reviewers_parser.add_argument(
        "--reviewers",
        nargs="*",
        default=None,
        help="Reviewer names (default: correctness, security, architecture, testing)",
    )
    reviewers_parser.add_argument(
        "--cwd",
        default=".",
        help="Working directory (default: current directory)",
    )

    # --- orchestrate ---
    orch_parser = subparsers.add_parser(
        "orchestrate",
        help="Run the full lifecycle orchestrator",
    )
    orch_parser.add_argument(
        "task",
        help="Task description, issue number (#N), or PR number",
    )
    orch_parser.add_argument("--cwd", default=".", help="Working directory")
    orch_parser.add_argument("--skip-planning", action="store_true")
    orch_parser.add_argument("--reviewers", nargs="*", default=None)
    orch_parser.add_argument("--max-rounds", type=int, default=10)
    orch_parser.add_argument("--phases", nargs="*", default=None)
    orch_parser.add_argument("--pr", type=int, default=None)

    # --- summary ---
    summary_parser = subparsers.add_parser(
        "summary",
        help="Print a human-readable summary of a completed run",
    )
    summary_parser.add_argument(
        "run_context_file",
        help="Path to the run_context.json file",
    )

    # --- debug ---
    debug_parser = subparsers.add_parser(
        "debug",
        help="Inspect sessions from a previous run",
    )
    debug_sub = debug_parser.add_subparsers(dest="debug_command", required=True)

    # debug sessions
    sessions_parser = debug_sub.add_parser(
        "sessions",
        help="List sessions from a run context file",
    )
    sessions_parser.add_argument(
        "run_context_file",
        help="Path to the run context JSON file",
    )

    # debug session
    session_parser = debug_sub.add_parser(
        "session",
        help="Show details for a specific session",
    )
    session_parser.add_argument(
        "session_id",
        help="Session ID to inspect",
    )
    session_parser.add_argument(
        "--cwd",
        default=".",
        help="Project directory (for finding session files)",
    )

    # debug resume
    resume_parser = debug_sub.add_parser(
        "resume",
        help="Resume a session with a follow-up prompt",
    )
    resume_parser.add_argument("session_id", help="Session ID to resume")
    resume_parser.add_argument(
        "prompt",
        nargs="?",
        default=None,
        help="Follow-up prompt (omit to read from stdin)",
    )
    resume_parser.add_argument("--cwd", default=".")

    args = parser.parse_args(argv)
    _configure_logging(args.verbose)

    # Validate numeric arguments
    if args.max_cost <= 0:
        print(
            f"Error: --max-cost must be a positive number, got: {args.max_cost}",
            file=sys.stderr,
        )
        sys.exit(2)
    if args.max_depth < 1:
        print(
            f"Error: --max-depth must be >= 1, got: {args.max_depth}",
            file=sys.stderr,
        )
        sys.exit(2)

    # Read-only commands bypass RunContext creation and the tracking epilogue
    if args.command == "summary":
        _cmd_summary(args)
        return

    # Dry-run mode: print resolved config without running agents
    if args.dry_run:
        if args.command == "run-agent":
            _dry_run_agent(args)
        elif args.command == "run-reviewers":
            _dry_run_reviewers(args)
        else:
            print(f"--dry-run is not supported for '{args.command}'", file=sys.stderr)
            sys.exit(1)
        return

    run_context = RunContext(
        max_depth=args.max_depth,
        max_cost_usd=args.max_cost,
    )

    try:
        if args.command == "run-agent":
            result = asyncio.run(_cmd_run_agent(args, run_context))
        elif args.command == "run-reviewers":
            result = asyncio.run(_cmd_run_reviewers(args, run_context))
        elif args.command == "orchestrate":
            result = asyncio.run(_cmd_orchestrate(args, run_context))
        elif args.command == "debug":
            result = _cmd_debug(args, run_context)
        else:
            parser.print_help()
            sys.exit(1)
            return

    except RecursionLimitError as e:
        result = _error_result(str(e), run_context)
    except CostLimitError as e:
        result = _error_result(str(e), run_context)

    # Always include tracking in output
    if isinstance(result, dict) and "tracking" not in result:
        result["tracking"] = run_context.summary()

    print(json.dumps(result, indent=2))

    # Save run context inside the run directory for later debugging
    run_context.save()

    if isinstance(result, dict) and not result.get("success", True):
        sys.exit(1)


def _error_result(message: str, run_context: RunContext) -> dict:
    return {
        "success": False,
        "error": message,
        "tracking": run_context.summary(),
    }


def _configure_logging(verbose: bool) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )


def _resolve_prompt(args: argparse.Namespace) -> str:
    """Resolve prompt from argument, file, or stdin."""
    if args.prompt:
        return args.prompt
    if hasattr(args, "prompt_file") and args.prompt_file:
        return Path(args.prompt_file).read_text()
    if not sys.stdin.isatty():
        return sys.stdin.read()
    logger.error("No prompt provided (use argument, --prompt-file, or pipe to stdin)")
    sys.exit(1)


def _dry_run_agent(args: argparse.Namespace) -> None:
    """Print resolved run-agent configuration without spawning agents."""
    from implement_cli.sdk import DEFAULT_TOOLS
    from implement_cli.types import Phase

    prompt = _resolve_prompt(args)
    phase = Phase(args.phase)
    tools = args.tools or DEFAULT_TOOLS.get(phase, [])
    cwd = Path(args.cwd).resolve()
    model = args.model or "(default)"

    print("=== DRY RUN: run-agent ===")
    print(f"Phase: {phase.value}")
    print(f"Role: {args.role}")
    print(f"CWD: {cwd}")
    print(f"Model: {model}")
    print(f"Tools: {', '.join(tools)}")
    if args.session_id:
        print(f"Session ID: {args.session_id}")
    if args.context_files:
        print(f"Context Files: {', '.join(args.context_files)}")
    print()
    print("--- Prompt ---")
    print(prompt)


def _dry_run_reviewers(args: argparse.Namespace) -> None:
    """Print resolved run-reviewers configuration without spawning agents."""
    from implement_cli.prompts import load_prompt
    from implement_cli.types import DEFAULT_REVIEWERS, VALID_REVIEWERS

    reviewers = args.reviewers or list(DEFAULT_REVIEWERS)

    for reviewer in reviewers:
        if reviewer not in VALID_REVIEWERS:
            print(
                f"Unknown reviewer {reviewer!r}. Valid reviewers: {VALID_REVIEWERS}",
                file=sys.stderr,
            )
            sys.exit(1)

    cwd = Path(args.cwd).resolve()

    print("=== DRY RUN: run-reviewers ===")
    print(f"PR: #{args.pr}")
    print(f"Round: {args.round}")
    print(f"CWD: {cwd}")

    for reviewer in reviewers:
        prompt = load_prompt(
            reviewer,
            PR_NUMBER=str(args.pr),
            ROUND_NUMBER=str(args.round),
        )
        print()
        print(f"--- Reviewer: {reviewer} ---")
        print(prompt)


async def _cmd_run_agent(args: argparse.Namespace, run_context: RunContext) -> dict:
    """Run a single agent."""
    from implement_cli.sdk import run_agent
    from implement_cli.types import Phase

    prompt = _resolve_prompt(args)
    phase = Phase(args.phase)

    result = await run_agent(
        prompt,
        phase=phase,
        role=args.role,
        cwd=Path(args.cwd).resolve(),
        run_context=run_context,
        session_id=args.session_id,
        model=args.model,
        allowed_tools=args.tools,
        context_files=args.context_files,
    )

    return {
        "success": not result.is_error,
        "result": result.to_dict(),
    }


async def _cmd_run_reviewers(args: argparse.Namespace, run_context: RunContext) -> dict:
    """Run parallel reviewers."""
    from implement_cli.review import run_parallel_reviewers

    from implement_cli.types import DEFAULT_REVIEWERS

    reviewers = args.reviewers or list(DEFAULT_REVIEWERS)

    results = await run_parallel_reviewers(
        reviewers,
        pr_number=args.pr,
        round_number=args.round,
        cwd=Path(args.cwd).resolve(),
        run_context=run_context,
    )

    return {
        "success": all(not r.is_error for r in results.values()),
        "reviewers": {
            name: result.to_dict()
            for name, result in results.items()
        },
    }


async def _cmd_orchestrate(args: argparse.Namespace, run_context: RunContext) -> dict:
    """Run the full lifecycle orchestrator."""
    from implement_cli.orchestrate import build_config, run_lifecycle

    config = build_config(args)
    results = await run_lifecycle(config, run_context=run_context)

    return {
        "success": all(r.success for r in results),
        "phases": [
            {
                "phase": r.phase.value,
                "success": r.success,
                "pr_number": r.pr_number,
                "session_id": r.session_id,
                "summary": r.summary,
                "error": r.error,
            }
            for r in results
        ],
        "pr_number": next((r.pr_number for r in results if r.pr_number), None),
    }


def _cmd_summary(args: argparse.Namespace) -> None:
    """Print a human-readable summary of a completed run."""
    from implement_cli.summary import format_summary

    path = Path(args.run_context_file)
    if not path.exists():
        print(f"Error: file not found: {path}", file=sys.stderr)
        sys.exit(1)

    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        print(f"Error: invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)

    print(format_summary(data))


def _cmd_debug(args: argparse.Namespace, run_context: RunContext) -> dict:
    """Debug subcommands — inspect sessions from previous runs."""
    if args.debug_command == "sessions":
        return _debug_sessions(args)
    elif args.debug_command == "session":
        return _debug_session(args)
    elif args.debug_command == "resume":
        return asyncio.run(_debug_resume(args, run_context))
    return {"error": f"Unknown debug command: {args.debug_command}"}


def _debug_sessions(args: argparse.Namespace) -> dict:
    """List sessions from a run context file."""
    path = Path(args.run_context_file)
    if not path.exists():
        return {"error": f"File not found: {path}"}

    data = json.loads(path.read_text())
    sessions = data.get("sessions", [])

    return {
        "success": True,
        "total_cost_usd": data.get("total_cost_usd"),
        "total_sessions": len(sessions),
        "elapsed_seconds": data.get("elapsed_seconds"),
        "sessions": [
            {
                "session_id": s["session_id"],
                "phase": s["phase"],
                "role": s["role"],
                "cost_usd": s["cost_usd"],
                "is_error": s["is_error"],
                "depth": s["depth"],
            }
            for s in sessions
        ],
    }


def _debug_session(args: argparse.Namespace) -> dict:
    """Show details for a specific session using claude-agent-sdk."""
    try:
        from claude_agent_sdk import get_session_messages
    except ImportError:
        return {"error": "claude-agent-sdk not available for session inspection"}

    messages = get_session_messages(args.session_id, limit=50)
    return {
        "success": True,
        "session_id": args.session_id,
        "message_count": len(messages),
        "messages": [
            {
                "type": getattr(m, "type", type(m).__name__),
                "uuid": getattr(m, "uuid", None),
            }
            for m in messages
        ],
    }


async def _debug_resume(args: argparse.Namespace, run_context: RunContext) -> dict:
    """Resume a session with a follow-up prompt."""
    from implement_cli.sdk import run_agent
    from implement_cli.types import Phase

    prompt = args.prompt
    if not prompt and not sys.stdin.isatty():
        prompt = sys.stdin.read()
    if not prompt:
        return {"error": "No prompt provided for resume"}

    result = await run_agent(
        prompt,
        phase=Phase.REVIEW,  # Generic — tools don't matter much for follow-ups
        role="debug-resume",
        cwd=Path(args.cwd).resolve(),
        run_context=run_context,
        session_id=args.session_id,
    )

    return {
        "success": not result.is_error,
        "result": result.to_dict(),
    }
