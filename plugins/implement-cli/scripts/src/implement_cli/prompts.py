"""Prompt template loading and interpolation."""

from __future__ import annotations

from pathlib import Path


PROMPTS_DIR = Path(__file__).resolve().parents[3] / "assets" / "prompts"


def load_prompt(name: str, **variables: str) -> str:
    """Load a prompt template and interpolate variables.

    Args:
        name: Prompt template filename (without .md extension).
        **variables: Key-value pairs to interpolate into the template.
            Uses $KEY syntax in templates.

    Returns:
        The interpolated prompt string.

    Raises:
        FileNotFoundError: If the prompt template does not exist.
    """
    path = PROMPTS_DIR / f"{name}.md"
    template = path.read_text()
    for key, value in variables.items():
        template = template.replace(f"${key}", value)
    return template
