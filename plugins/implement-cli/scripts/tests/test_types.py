"""Tests for implement_cli.types."""

from implement_cli.types import (
    Finding,
    FindingDecision,
    OrchestratorConfig,
    Phase,
    PhaseResult,
    RefereeDecision,
    ReviewRoundResult,
    Severity,
)


def test_phase_values() -> None:
    assert Phase.PLAN.value == "plan"
    assert Phase.IMPLEMENT.value == "implement"
    assert Phase.REVIEW.value == "review"
    assert Phase.ADDRESS.value == "address"
    assert Phase.DOCS.value == "docs"
    assert Phase.VERIFY.value == "verify"
    assert Phase.MERGE.value == "merge"


def test_severity_values() -> None:
    assert Severity.ACTION_REQUIRED.value == "Action Required"
    assert Severity.RECOMMENDED.value == "Recommended"
    assert Severity.MINOR.value == "Minor"


def test_finding_decision_values() -> None:
    assert FindingDecision.ACCEPT.value == "Accept"
    assert FindingDecision.REJECT.value == "Reject"


def test_finding_creation() -> None:
    finding = Finding(
        description="Missing null check",
        severity=Severity.ACTION_REQUIRED,
        reviewer="review-correctness",
        file_path="src/main.py",
        line=42,
    )
    assert finding.description == "Missing null check"
    assert finding.severity == Severity.ACTION_REQUIRED
    assert finding.reviewer == "review-correctness"
    assert finding.file_path == "src/main.py"
    assert finding.line == 42
    assert finding.details is None


def test_finding_defaults() -> None:
    finding = Finding(
        description="Test",
        severity=Severity.MINOR,
        reviewer="review-testing",
    )
    assert finding.file_path is None
    assert finding.line is None
    assert finding.details is None


def test_referee_decision() -> None:
    finding = Finding(
        description="Test",
        severity=Severity.ACTION_REQUIRED,
        reviewer="review-correctness",
    )
    decision = RefereeDecision(
        finding=finding,
        decision=FindingDecision.REJECT,
        reasoning="Finding is incorrect",
    )
    assert decision.decision == FindingDecision.REJECT
    assert decision.reasoning == "Finding is incorrect"


def test_referee_decision_accept() -> None:
    finding = Finding(
        description="Missing error handling",
        severity=Severity.RECOMMENDED,
        reviewer="review-correctness",
    )
    decision = RefereeDecision(
        finding=finding,
        decision=FindingDecision.ACCEPT,
        reasoning="Valid finding that should be addressed",
    )
    assert decision.finding == finding
    assert decision.decision == FindingDecision.ACCEPT
    assert decision.reasoning == "Valid finding that should be addressed"


def test_review_round_result_defaults() -> None:
    result = ReviewRoundResult(round_number=1)
    assert result.round_number == 1
    assert result.findings == []
    assert result.decisions == []
    assert result.session_ids == {}


def test_phase_result() -> None:
    result = PhaseResult(
        phase=Phase.IMPLEMENT,
        success=True,
        session_id="abc123",
        pr_number=42,
        summary="Created PR #42",
    )
    assert result.phase == Phase.IMPLEMENT
    assert result.success is True
    assert result.pr_number == 42
    assert result.error is None


def test_orchestrator_config_defaults() -> None:
    config = OrchestratorConfig(cwd="/tmp/test")
    assert config.pr_number is None
    assert config.issue_number is None
    assert config.task_description == ""
    assert config.skip_planning is False
    assert config.max_review_rounds == 10
    assert len(config.reviewers) == 4
    assert "review-correctness" in config.reviewers
