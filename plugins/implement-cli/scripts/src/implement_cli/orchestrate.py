"""Main orchestrator for the implement-cli lifecycle.

Coordinates all phases: plan, implement, review/address loop, docs gate,
verify, and merge — delegating heavy work to claude-agent-sdk subprocesses.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import re
import sys
import tempfile
from pathlib import Path

from implement_cli.address import run_addresser
from implement_cli.implement import run_implementer
from implement_cli.merge import run_merger
from implement_cli.plan import run_planner
from implement_cli.review import run_parallel_reviewers
from implement_cli.types import OrchestratorConfig, Phase, PhaseResult
from implement_cli.verify import run_verifier

logger = logging.getLogger(__name__)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description="implement-cli orchestrator")
    parser.add_argument(
        "task",
        help="Task description, issue number (#N), or PR number",
    )
    parser.add_argument(
        "--cwd",
        default=".",
        help="Working directory (default: current directory)",
    )
    parser.add_argument(
        "--skip-planning",
        action="store_true",
        help="Skip the planning phase",
    )
    parser.add_argument(
        "--reviewers",
        nargs="*",
        default=None,
        help="Reviewer names to invoke (default: all four code reviewers)",
    )
    parser.add_argument(
        "--max-rounds",
        type=int,
        default=10,
        help="Maximum review/address rounds before escalation (default: 10)",
    )
    parser.add_argument(
        "--phases",
        nargs="*",
        default=None,
        help="Phases to run (default: all). Options: plan, implement, review, docs, verify, merge",
    )
    parser.add_argument(
        "--pr",
        type=int,
        default=None,
        help="Existing PR number (skip plan+implement, start at review)",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Enable verbose logging",
    )
    return parser.parse_args(argv)


def configure_logging(verbose: bool) -> None:
    """Configure logging for the orchestrator."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )


def parse_pr_number(text: str) -> int | None:
    """Extract PR number from implementer output."""
    match = re.search(r"PR_NUMBER:\s*(\d+)", text)
    if match:
        return int(match.group(1))
    match = re.search(r"#(\d+)", text)
    if match:
        return int(match.group(1))
    return None


def build_config(args: argparse.Namespace) -> OrchestratorConfig:
    """Build orchestrator config from parsed arguments."""
    task = args.task
    issue_number: int | None = None
    pr_number: int | None = args.pr

    # Parse leading token for issue number
    if task.startswith("#"):
        try:
            issue_number = int(task.lstrip("#").split()[0])
        except ValueError:
            pass

    reviewers = args.reviewers or [
        "review-correctness",
        "review-security",
        "review-architecture",
        "review-testing",
    ]

    return OrchestratorConfig(
        cwd=Path(args.cwd).resolve(),
        pr_number=pr_number,
        issue_number=issue_number,
        task_description=task,
        skip_planning=args.skip_planning,
        max_review_rounds=args.max_rounds,
        reviewers=reviewers,
    )


async def run_lifecycle(config: OrchestratorConfig) -> list[PhaseResult]:
    """Run the full implementation lifecycle.

    Args:
        config: Orchestrator configuration.

    Returns:
        A list of PhaseResult for each completed phase.
    """
    results: list[PhaseResult] = []
    pr_number = config.pr_number

    # Phase 1: Plan (if needed)
    if not config.skip_planning and pr_number is None:
        logger.info("=== Phase 1: Planning ===")
        plan_result = await run_planner(
            task_description=config.task_description,
            cwd=config.cwd,
        )
        results.append(
            PhaseResult(
                phase=Phase.PLAN,
                success=not plan_result.is_error,
                session_id=plan_result.session_id,
                summary=plan_result.text[:500],
            )
        )
        if plan_result.is_error:
            logger.error("Planning failed, stopping")
            return results

    # Phase 2-3: Implement & Create PR (if no PR provided)
    if pr_number is None:
        logger.info("=== Phase 2-3: Implement & Create PR ===")
        impl_result = await run_implementer(
            task_description=config.task_description,
            plan=results[-1].summary if results else None,
            issue_number=config.issue_number,
            skip_planning=config.skip_planning,
            cwd=config.cwd,
        )

        pr_number = parse_pr_number(impl_result.text)

        results.append(
            PhaseResult(
                phase=Phase.IMPLEMENT,
                success=not impl_result.is_error and pr_number is not None,
                session_id=impl_result.session_id,
                pr_number=pr_number,
                summary=impl_result.text[:500],
            )
        )

        if pr_number is None:
            logger.error("Implementer did not return a PR number, stopping")
            return results

    # Phase 4: Review/Address Loop
    logger.info("=== Phase 4: Review/Address Loop ===")
    review_phase = await _run_review_loop(config, pr_number)
    results.append(review_phase)

    if not review_phase.success:
        logger.error("Review loop did not converge, stopping")
        return results

    # Phase 4.5: Docs Compliance Gate
    logger.info("=== Phase 4.5: Docs Compliance Gate ===")
    docs_phase = await _run_docs_gate(config, pr_number)
    results.append(docs_phase)

    if not docs_phase.success:
        logger.error("Docs gate did not converge, stopping")
        return results

    # Phase 5: Verification
    logger.info("=== Phase 5: Verification ===")
    verify_result = await run_verifier(pr_number=pr_number, cwd=config.cwd)
    results.append(
        PhaseResult(
            phase=Phase.VERIFY,
            success=not verify_result.is_error,
            session_id=verify_result.session_id,
            pr_number=pr_number,
            summary=verify_result.text[:500],
        )
    )

    if verify_result.is_error:
        logger.error("Verification failed, stopping")
        return results

    # Phase 6: Merge
    logger.info("=== Phase 6: Merge ===")
    merge_result = await run_merger(pr_number=pr_number, cwd=config.cwd)
    results.append(
        PhaseResult(
            phase=Phase.MERGE,
            success=not merge_result.is_error,
            session_id=merge_result.session_id,
            pr_number=pr_number,
            summary=merge_result.text[:500],
        )
    )

    return results


async def _run_review_loop(
    config: OrchestratorConfig,
    pr_number: int,
) -> PhaseResult:
    """Run the review/address loop until clean or escalation.

    Returns a PhaseResult indicating success (clean exit) or failure (escalation).
    """
    session_ids: dict[str, str] = {}

    for round_num in range(1, config.max_review_rounds + 1):
        logger.info("--- Review Round %d ---", round_num)

        # Step A: Run reviewers in parallel
        reviewer_results = await run_parallel_reviewers(
            config.reviewers,
            pr_number=pr_number,
            round_number=round_num,
            cwd=config.cwd,
        )

        # Collect session IDs
        for name, result in reviewer_results.items():
            if result.session_id:
                session_ids[f"{name}-round-{round_num}"] = result.session_id

        # Step B: Check if any findings exist
        # The orchestrator (SKILL.md) does the actual refereeing. Here we just
        # pass the raw reviewer output back for the orchestrator to evaluate.
        all_text = "\n\n".join(
            f"## {name}\n{result.text}" for name, result in reviewer_results.items()
        )

        has_findings = _has_actionable_findings(all_text)

        if not has_findings:
            logger.info("Round %d: no actionable findings — review loop complete", round_num)
            return PhaseResult(
                phase=Phase.REVIEW,
                success=True,
                pr_number=pr_number,
                summary=f"Review loop completed in {round_num} round(s) with no actionable findings.",
            )

        # Step C-D: Write findings and run addresser
        findings_path = Path(tempfile.gettempdir()) / f"implement-findings-pr-{pr_number}-round-{round_num}.md"
        findings_path.write_text(all_text)

        address_result = await run_addresser(
            pr_number=pr_number,
            round_number=round_num,
            findings_path=findings_path,
            cwd=config.cwd,
        )

        if address_result.session_id:
            session_ids[f"addresser-round-{round_num}"] = address_result.session_id

    # Escalation
    logger.warning(
        "Review loop did not converge after %d rounds — escalating",
        config.max_review_rounds,
    )
    return PhaseResult(
        phase=Phase.REVIEW,
        success=False,
        pr_number=pr_number,
        summary=f"Review loop escalated after {config.max_review_rounds} rounds.",
        error="Review loop did not converge — requires human review.",
    )


async def _run_docs_gate(
    config: OrchestratorConfig,
    pr_number: int,
) -> PhaseResult:
    """Run the docs compliance gate loop.

    Same pattern as the review loop but only the docs reviewer.
    """
    for round_num in range(1, config.max_review_rounds + 1):
        logger.info("--- Docs Gate Round %d ---", round_num)

        reviewer_results = await run_parallel_reviewers(
            ["review-docs"],
            pr_number=pr_number,
            round_number=round_num,
            cwd=config.cwd,
        )

        docs_result = reviewer_results.get("review-docs")
        if docs_result is None:
            return PhaseResult(
                phase=Phase.DOCS,
                success=False,
                pr_number=pr_number,
                error="Docs reviewer failed to run.",
            )

        if not _has_actionable_findings(docs_result.text):
            logger.info("Docs gate round %d: no actionable findings — gate passed", round_num)
            return PhaseResult(
                phase=Phase.DOCS,
                success=True,
                pr_number=pr_number,
                summary=f"Docs compliance gate passed in {round_num} round(s).",
            )

        findings_path = Path(tempfile.gettempdir()) / f"implement-docs-findings-pr-{pr_number}-round-{round_num}.md"
        findings_path.write_text(docs_result.text)

        await run_addresser(
            pr_number=pr_number,
            round_number=round_num,
            findings_path=findings_path,
            cwd=config.cwd,
        )

    return PhaseResult(
        phase=Phase.DOCS,
        success=False,
        pr_number=pr_number,
        error=f"Docs gate did not converge after {config.max_review_rounds} rounds.",
    )


def _has_actionable_findings(text: str) -> bool:
    """Heuristic: check if reviewer output contains actionable findings."""
    lower = text.lower()
    # If reviewers explicitly say no findings / code is correct
    no_findings_phrases = [
        "no actionable findings",
        "no findings",
        "code is correct",
        "looks solid",
        "no issues found",
        "the code is correct",
        "architecture looks solid",
        "test coverage and quality look solid",
        "security and requirements look solid",
    ]
    has_no_findings = any(phrase in lower for phrase in no_findings_phrases)

    # Check for finding sections
    has_findings_section = bool(
        re.search(r"###\s*(action required|recommended)", lower)
    )

    return has_findings_section and not has_no_findings


def main(argv: list[str] | None = None) -> None:
    """Entry point for the orchestrator CLI."""
    args = parse_args(argv)
    configure_logging(args.verbose)

    config = build_config(args)

    logger.info("Starting implement-cli lifecycle")
    logger.info("Task: %s", config.task_description[:200])
    logger.info("CWD: %s", config.cwd)

    results = asyncio.run(run_lifecycle(config))

    # Output results as JSON
    output = {
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
        "overall_success": all(r.success for r in results),
        "pr_number": next((r.pr_number for r in results if r.pr_number), None),
    }

    print(json.dumps(output, indent=2))

    if not output["overall_success"]:
        sys.exit(1)
