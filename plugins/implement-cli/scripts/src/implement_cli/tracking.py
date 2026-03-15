"""Observability: cost tracking, session registry, recursion depth enforcement."""

from __future__ import annotations

import json
import logging
import time
from dataclasses import dataclass, field
from pathlib import Path

logger = logging.getLogger(__name__)


@dataclass
class SessionRecord:
    """A record of a single agent invocation."""

    session_id: str
    phase: str
    role: str
    cost_usd: float | None = None
    input_tokens: int = 0
    output_tokens: int = 0
    duration_ms: int = 0
    is_error: bool = False
    depth: int = 0
    parent_session_id: str | None = None


@dataclass
class RunContext:
    """Tracks cumulative state across an entire orchestrator run.

    Thread-safe for single-threaded async usage (asyncio is single-threaded).
    """

    max_depth: int = 5
    max_cost_usd: float = 50.0
    current_depth: int = 0
    sessions: list[SessionRecord] = field(default_factory=list)
    _total_cost_usd: float = 0.0
    _total_input_tokens: int = 0
    _total_output_tokens: int = 0
    _start_time: float = field(default_factory=time.time)

    def check_depth(self) -> None:
        """Raise if current depth exceeds max_depth."""
        if self.current_depth >= self.max_depth:
            raise RecursionLimitError(
                f"Recursion depth {self.current_depth} exceeds limit {self.max_depth}"
            )

    def check_cost(self) -> None:
        """Raise if cumulative cost exceeds max_cost_usd."""
        if self._total_cost_usd >= self.max_cost_usd:
            raise CostLimitError(
                f"Cumulative cost ${self._total_cost_usd:.4f} exceeds limit ${self.max_cost_usd:.2f}"
            )

    def enter_depth(self) -> int:
        """Increment depth and return the new level."""
        self.check_depth()
        self.current_depth += 1
        return self.current_depth

    def exit_depth(self) -> int:
        """Decrement depth and return the new level."""
        self.current_depth = max(0, self.current_depth - 1)
        return self.current_depth

    def record_session(self, record: SessionRecord) -> None:
        """Record a completed session and update cumulative totals."""
        record.depth = self.current_depth
        self.sessions.append(record)

        if record.cost_usd is not None:
            self._total_cost_usd += record.cost_usd
        self._total_input_tokens += record.input_tokens
        self._total_output_tokens += record.output_tokens

        logger.info(
            "Session %s (%s/%s): cost=$%.4f, tokens=%d/%d, depth=%d",
            record.session_id,
            record.phase,
            record.role,
            record.cost_usd or 0,
            record.input_tokens,
            record.output_tokens,
            record.depth,
        )

        # Check cost after recording
        self.check_cost()

    @property
    def total_cost_usd(self) -> float:
        return self._total_cost_usd

    @property
    def total_input_tokens(self) -> int:
        return self._total_input_tokens

    @property
    def total_output_tokens(self) -> int:
        return self._total_output_tokens

    @property
    def elapsed_seconds(self) -> float:
        return time.time() - self._start_time

    def summary(self) -> dict:
        """Return a summary dict suitable for JSON output."""
        return {
            "total_cost_usd": round(self._total_cost_usd, 4),
            "total_input_tokens": self._total_input_tokens,
            "total_output_tokens": self._total_output_tokens,
            "total_sessions": len(self.sessions),
            "max_depth_reached": max((s.depth for s in self.sessions), default=0),
            "elapsed_seconds": round(self.elapsed_seconds, 1),
            "sessions": [
                {
                    "session_id": s.session_id,
                    "phase": s.phase,
                    "role": s.role,
                    "cost_usd": s.cost_usd,
                    "input_tokens": s.input_tokens,
                    "output_tokens": s.output_tokens,
                    "duration_ms": s.duration_ms,
                    "is_error": s.is_error,
                    "depth": s.depth,
                }
                for s in self.sessions
            ],
        }

    def save(self, path: Path) -> None:
        """Persist the run context to a JSON file for later inspection."""
        path.write_text(json.dumps(self.summary(), indent=2))
        logger.info("Run context saved to %s", path)


class RecursionLimitError(RuntimeError):
    """Raised when recursion depth exceeds the configured limit."""


class CostLimitError(RuntimeError):
    """Raised when cumulative cost exceeds the configured limit."""
