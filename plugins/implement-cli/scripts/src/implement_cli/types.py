"""Shared types for the implement-cli orchestrator."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path


class Phase(Enum):
    PLAN = "plan"
    IMPLEMENT = "implement"
    REVIEW = "review"
    ADDRESS = "address"
    DOCS = "docs"
    VERIFY = "verify"
    MERGE = "merge"


class Severity(Enum):
    ACTION_REQUIRED = "Action Required"
    RECOMMENDED = "Recommended"
    MINOR = "Minor"


class FindingDecision(Enum):
    ACCEPT = "Accept"
    DOWNGRADE = "Downgrade"
    REJECT = "Reject"


@dataclass
class Finding:
    """A review finding from a specialist reviewer."""

    description: str
    severity: Severity
    reviewer: str
    file_path: str | None = None
    line: int | None = None
    details: str | None = None


@dataclass
class RefereeDecision:
    """A referee's decision on a review finding."""

    finding: Finding
    decision: FindingDecision
    reasoning: str
    adjusted_severity: Severity | None = None


@dataclass
class ReviewRoundResult:
    """The result of a single review round."""

    round_number: int
    findings: list[Finding] = field(default_factory=list)
    decisions: list[RefereeDecision] = field(default_factory=list)
    session_ids: dict[str, str] = field(default_factory=dict)


@dataclass
class PhaseResult:
    """The result of a lifecycle phase."""

    phase: Phase
    success: bool
    session_id: str | None = None
    pr_number: int | None = None
    summary: str = ""
    error: str | None = None


@dataclass
class OrchestratorConfig:
    """Configuration for the orchestrator."""

    cwd: str | Path
    pr_number: int | None = None
    issue_number: int | None = None
    task_description: str = ""
    skip_planning: bool = False
    max_review_rounds: int = 10
    reviewers: list[str] = field(
        default_factory=lambda: [
            "review-correctness",
            "review-security",
            "review-architecture",
            "review-testing",
        ]
    )
