"""Full lifecycle orchestrator.

Coordinates all phases: plan, implement, review/address loop, docs gate,
verify, and merge — delegating heavy work to claude-agent-sdk subprocesses.

This module retains the end-to-end orchestration capability for future
experimentation. The SKILL.md orchestrator should call targeted subcommands
(run-agent, run-reviewers) rather than this full pipeline.
"""

from __future__ import annotations

import argparse
import logging
import re
from pathlib import Path

from implement_cli.address import run_addresser
from implement_cli.implement import run_implementer
from implement_cli.merge import run_merger
from implement_cli.plan import run_planner
from implement_cli.review import run_parallel_reviewers
from implement_cli.tracking import RunContext
from implement_cli.types import DEFAULT_REVIEWERS, OrchestratorConfig, Phase, PhaseResult
from implement_cli.verify import run_verifier

logger = logging.getLogger(__name__)


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
        except (ValueError, IndexError):
            pass

    reviewers = args.reviewers or list(DEFAULT_REVIEWERS)

    return OrchestratorConfig(
        cwd=Path(args.cwd).resolve(),
        pr_number=pr_number,
        issue_number=issue_number,
        task_description=task,
        skip_planning=args.skip_planning,
        max_review_rounds=args.max_rounds,
        reviewers=reviewers,
    )


async def run_lifecycle(
    config: OrchestratorConfig,
    *,
    run_context: RunContext | None = None,
) -> list[PhaseResult]:
    """Run the full implementation lifecycle.

    Args:
        config: Orchestrator configuration.
        run_context: Optional RunContext for tracking costs and enforcing limits.

    Returns:
        A list of PhaseResult for each completed phase.
    """
    ctx = run_context or RunContext()
    results: list[PhaseResult] = []
    pr_number = config.pr_number

    # Phase 1: Plan (if needed)
    if not config.skip_planning and pr_number is None:
        logger.info("=== Phase 1: Planning ===")
        plan_result = await run_planner(
            task_description=config.task_description,
            cwd=config.cwd,
            run_context=ctx,
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
            run_context=ctx,
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
    review_phase = await _run_review_loop(config, pr_number, ctx)
    results.append(review_phase)

    if not review_phase.success:
        logger.error("Review loop did not converge, stopping")
        return results

    # Phase 4.5: Docs Compliance Gate
    logger.info("=== Phase 4.5: Docs Compliance Gate ===")
    docs_phase = await _run_docs_gate(config, pr_number, ctx)
    results.append(docs_phase)

    if not docs_phase.success:
        logger.error("Docs gate did not converge, stopping")
        return results

    # Phase 5: Verification
    logger.info("=== Phase 5: Verification ===")
    verify_result = await run_verifier(pr_number=pr_number, cwd=config.cwd, run_context=ctx)
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
    merge_result = await run_merger(pr_number=pr_number, cwd=config.cwd, run_context=ctx)
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
    ctx: RunContext,
) -> PhaseResult:
    """Run the review/address loop until clean or escalation."""
    for round_num in range(1, config.max_review_rounds + 1):
        logger.info("--- Review Round %d ---", round_num)

        reviewer_results = await run_parallel_reviewers(
            config.reviewers,
            pr_number=pr_number,
            round_number=round_num,
            cwd=config.cwd,
            run_context=ctx,
        )

        all_text = "\n\n".join(
            f"## {name}\n{result.text}" for name, result in reviewer_results.items()
        )

        if not has_actionable_findings(all_text):
            logger.info("Round %d: no actionable findings — review loop complete", round_num)
            return PhaseResult(
                phase=Phase.REVIEW,
                success=True,
                pr_number=pr_number,
                summary=f"Review loop completed in {round_num} round(s) with no actionable findings.",
            )

        findings_path = ctx.artifact_path(f"findings-pr-{pr_number}-round-{round_num}.md")
        findings_path.write_text(all_text)

        await run_addresser(
            pr_number=pr_number,
            round_number=round_num,
            findings_path=findings_path,
            cwd=config.cwd,
            run_context=ctx,
        )

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
    ctx: RunContext,
) -> PhaseResult:
    """Run the docs compliance gate loop."""
    for round_num in range(1, config.max_review_rounds + 1):
        logger.info("--- Docs Gate Round %d ---", round_num)

        reviewer_results = await run_parallel_reviewers(
            ["review-docs"],
            pr_number=pr_number,
            round_number=round_num,
            cwd=config.cwd,
            run_context=ctx,
        )

        docs_result = reviewer_results.get("review-docs")
        if docs_result is None:
            return PhaseResult(
                phase=Phase.DOCS,
                success=False,
                pr_number=pr_number,
                error="Docs reviewer failed to run.",
            )

        if not has_actionable_findings(docs_result.text):
            logger.info("Docs gate round %d: no actionable findings — gate passed", round_num)
            return PhaseResult(
                phase=Phase.DOCS,
                success=True,
                pr_number=pr_number,
                summary=f"Docs compliance gate passed in {round_num} round(s).",
            )

        findings_path = ctx.artifact_path(f"docs-findings-pr-{pr_number}-round-{round_num}.md")
        findings_path.write_text(docs_result.text)

        await run_addresser(
            pr_number=pr_number,
            round_number=round_num,
            findings_path=findings_path,
            cwd=config.cwd,
            run_context=ctx,
        )

    return PhaseResult(
        phase=Phase.DOCS,
        success=False,
        pr_number=pr_number,
        error=f"Docs gate did not converge after {config.max_review_rounds} rounds.",
    )


def has_actionable_findings(text: str) -> bool:
    """Heuristic: check if reviewer output contains actionable findings.

    The presence of findings section headers (### Action Required, ### Recommended)
    takes precedence over "no findings" phrases, since those phrases may appear
    in summary sections alongside real findings.
    """
    lower = text.lower()

    has_findings_section = bool(
        re.search(r"###\s*(action required|recommended)", lower)
    )

    # If there are findings section headers, trust them — the reviewer found something
    if has_findings_section:
        return True

    # No findings sections — check for explicit "all clear" signals
    no_findings_phrases = [
        "no actionable findings",
        "no findings",
        "no issues found",
    ]
    has_no_findings = any(phrase in lower for phrase in no_findings_phrases)
    if has_no_findings:
        return False

    # No findings sections and no explicit "all clear" — assume no findings
    return False
