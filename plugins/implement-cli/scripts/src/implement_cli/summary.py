"""Human-readable summary formatting for run context data."""

from __future__ import annotations

from collections import defaultdict


# Display order for phases
_PHASE_ORDER = ["plan", "implement", "review", "address", "docs", "verify", "merge"]


def format_summary(data: dict) -> str:
    """Format run context data as a human-readable summary table.

    Args:
        data: Parsed run_context.json dict with keys: run_dir, total_cost_usd,
              total_input_tokens, total_output_tokens, sessions, elapsed_seconds.

    Returns:
        Formatted multi-line string with phase table, totals, and verdict.
    """
    run_dir = data.get("run_dir", "unknown")
    sessions = data.get("sessions", [])

    # Aggregate sessions by phase
    phases: dict[str, dict] = defaultdict(
        lambda: {"cost": 0.0, "duration_s": 0, "sessions": 0, "has_error": False}
    )
    for s in sessions:
        phase = s.get("phase", "unknown")
        p = phases[phase]
        p["cost"] += s.get("cost_usd") or 0.0
        p["duration_s"] += (s.get("duration_ms") or 0) / 1000
        p["sessions"] += 1
        if s.get("is_error"):
            p["has_error"] = True

    # Sort phases by canonical order, unknown phases at the end
    phase_names = sorted(
        phases.keys(),
        key=lambda name: (
            _PHASE_ORDER.index(name) if name in _PHASE_ORDER else len(_PHASE_ORDER),
            name,
        ),
    )

    # Build table rows
    rows: list[tuple[str, str, str, str, str]] = []
    total_cost = 0.0
    total_duration = 0
    total_sessions = 0
    failed_phases: list[str] = []

    for name in phase_names:
        p = phases[name]
        status = "FAIL" if p["has_error"] else "PASS"
        cost = p["cost"]
        duration = int(p["duration_s"])
        count = p["sessions"]

        total_cost += cost
        total_duration += duration
        total_sessions += count
        if p["has_error"]:
            failed_phases.append(name)

        rows.append((
            name,
            status,
            f"${cost:.2f}",
            f"{duration}s",
            str(count),
        ))

    # Column widths
    header = ("Phase", "Status", "Cost", "Duration", "Sessions")
    col_widths = [len(h) for h in header]
    for row in rows:
        for i, cell in enumerate(row):
            col_widths[i] = max(col_widths[i], len(cell))

    # Ensure minimum widths for readability
    col_widths[0] = max(col_widths[0], 16)

    def fmt_row(cells: tuple[str, ...]) -> str:
        parts = []
        for i, cell in enumerate(cells):
            parts.append(cell.ljust(col_widths[i]))
        return "  ".join(parts)

    table_width = sum(col_widths) + 2 * (len(col_widths) - 1)

    lines: list[str] = []
    lines.append(f"Run Summary: {run_dir}")
    lines.append("\u2550" * table_width)
    lines.append(fmt_row(header))
    lines.append("\u2500" * table_width)
    for row in rows:
        lines.append(fmt_row(row))
    lines.append("\u2500" * table_width)

    # Totals row
    lines.append(fmt_row((
        "Total",
        "",
        f"${total_cost:.2f}",
        f"{total_duration}s",
        str(total_sessions),
    )))

    # Token summary
    in_tokens = data.get("total_input_tokens", 0)
    out_tokens = data.get("total_output_tokens", 0)
    lines.append(f"Tokens: {in_tokens:,} in / {out_tokens:,} out")

    # Verdict
    lines.append("")
    if failed_phases:
        lines.append(f"Result: FAILED ({', '.join(failed_phases)})")
    else:
        lines.append("Result: ALL PHASES PASSED")

    return "\n".join(lines)
