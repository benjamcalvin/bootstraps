#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "docs-check.py"
BASE = HERE / "fixtures" / "base"
CHANGE = HERE / "fixtures" / "change"
GIT_ENV = {
    **os.environ,
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "Fixture",
    "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
    "GIT_COMMITTER_NAME": "Fixture",
    "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
}

BASE_EXPECTED = [
    "docs/guide.md:5: WARNING: doc cites an issue number: #42",
    "docs/specs/core.md:10: WARNING: glossary term not found in covered code: Gizmo",
]
CHANGE_EXPECTED = [
    "AGENTS.md:6: ERROR: instruction file is 7 lines, over its 5-line budget",
    "docs-check.toml:9: ERROR: line budget for AGENTS.md raised from 4 to 5; budgets only fall",
    "docs/guide.md:5: WARNING: doc cites an issue number: #42",
    "docs/guide.md:7: ERROR: backticked path does not exist: scripts/release.sh",
    "docs/guide.md:7: ERROR: link target does not exist: runbook.md",
    "docs/guide.md:7: ERROR: npm script not defined: deploy",
    "docs/specs/core.md:3: WARNING: covered code changed by 10 lines since main but this spec did not",
    "docs/specs/core.md:10: WARNING: glossary term not found in covered code: Gizmo",
    "lib/Agents.md:1: ERROR: instruction file name is not exact: Agents.md (use AGENTS.md or CLAUDE.md)",
    "src/app.py:3: ERROR: added comment has a step label: Step 3:",
    "src/app.py:8: ERROR: added comment cites a tracker reference: #123",
    "src/app.py:10: ERROR: added comment records history: previously",
    "src/util.js:1: ERROR: added comment records history: changed from",
    "tools/CLAUDE.md:1: ERROR: CLAUDE.md does not import @AGENTS.md",
]
INSTALL_EXPECTED = [
    "docs/guide.md:5: WARNING: doc cites an issue number: #42",
    "docs/specs/core.md:10: WARNING: glossary term not found in covered code: Gizmo",
]
STALE_EXPECTED = INSTALL_EXPECTED + [
    "docs-check.toml:8: WARNING: baseline entry no longer occurs; run --write-baseline to drop it: "
    "docs/legacy.md: link target does not exist: ./gone.md",
]

failures = []


def git(repo, *args):
    subprocess.run(["git", *args], cwd=repo, env=GIT_ENV, check=True, capture_output=True)


def docs_check(repo, *args):
    result = subprocess.run([sys.executable, str(SCRIPT), *args], cwd=repo, env=GIT_ENV, capture_output=True, text=True)
    return result.returncode, result.stdout.splitlines(), result.stderr


def expect(name, actual, expected):
    if actual != expected:
        failures.append(f"{name}:\n  expected: {expected!r}\n  actual:   {actual!r}")


def expect_run(name, result, code, lines):
    actual_code, actual_lines, stderr = result
    expect(f"{name} exit code (stderr: {stderr.strip()})", actual_code, code)
    missing = [line for line in lines if line not in actual_lines]
    unexpected = [line for line in actual_lines if line not in lines]
    if missing or unexpected:
        failures.append(f"{name} output:\n" + "".join(f"  missing:    {line}\n" for line in missing)
                        + "".join(f"  unexpected: {line}\n" for line in unexpected))


def commit_tree(repo, source, message):
    shutil.copytree(source, repo, dirs_exist_ok=True)
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "--no-verify", "-m", message)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp) / "repo"
        repo.mkdir()
        git(repo, "init", "-q", "-b", "main")
        commit_tree(repo, BASE, "base")

        expect_run("warnings and baselined errors on the base", docs_check(repo), 0, BASE_EXPECTED)

        git(repo, "checkout", "-q", "-b", "change")
        commit_tree(repo, CHANGE, "change")
        expect_run("violations the change adds", docs_check(repo), 1, CHANGE_EXPECTED)
        expect_run("explicit --base", docs_check(repo, "--base", "main"), 1, CHANGE_EXPECTED)

        config = (repo / "docs-check.toml").read_text()
        expect_run("--write-baseline never adds entries", docs_check(repo, "--write-baseline"), 1, CHANGE_EXPECTED)
        expect("baseline after --write-baseline", (repo / "docs-check.toml").read_text(), config)

        install = Path(tmp) / "install"
        install.mkdir()
        git(install, "init", "-q", "-b", "main")
        shutil.copytree(repo, install, dirs_exist_ok=True, ignore=shutil.ignore_patterns(".git", "docs-check.toml"))
        (install / "tools" / "AGENTS.md").write_text("Tool notes.\n" * 205)
        git(install, "add", "-A")
        git(install, "commit", "-q", "--no-verify", "-m", "install")
        expect_run("install writes the current baseline", docs_check(install, "--write-baseline"), 0, INSTALL_EXPECTED)
        written = (install / "docs-check.toml").read_text()
        for needle in ('"docs/legacy.md: link target does not exist: ./gone.md",', '"tools/AGENTS.md" = 205'):
            if needle not in written:
                failures.append(f"installed docs-check.toml lacks {needle!r}:\n{written}")
        expect_run("rerun after install", docs_check(install), 0, INSTALL_EXPECTED)

        (install / "docs" / "legacy.md").write_text("# Legacy\n")
        expect_run("fixed baseline entry is reported stale", docs_check(install), 0, STALE_EXPECTED)
        docs_check(install, "--write-baseline")
        if "docs/legacy.md" in (install / "docs-check.toml").read_text():
            failures.append("--write-baseline did not drop the fixed baseline entry")

        edge = Path(tmp) / "edge"
        edge.mkdir()
        git(edge, "init", "-q", "-b", "main")
        (edge / "docs-check.toml").write_text('default_budget = 200\n[budgets]\n"AGENTS.md" = 10\n')
        (edge / "AGENTS.md").write_text("Notes.\n")
        (edge / "my file.py").write_text("x = 1\n")
        (edge / "latin.txt").write_bytes(b"caf\xe9\n")
        (edge / ".gitignore").write_text("build/\n")
        git(edge, "add", "-A")
        git(edge, "commit", "-q", "--no-verify", "-m", "base")
        git(edge, "checkout", "-q", "-b", "change")
        (edge / "docs-check.toml").write_text("default_budget = 200\n")
        (edge / "AGENTS.md").write_text("Notes.\n" * 20)
        (edge / "my file.py").write_text("x = 1\n# previously a thing\n")
        (edge / "latin.txt").write_bytes(b"caf\xe9 more\n")
        (edge / "tags.py").write_text("y = 1  #123\n#42 done\n#!not a tracker\n")
        (edge / "README.md").write_text("Output goes to `build/out.txt` and `build/` and `src/build/`.\n")
        git(edge, "add", "-A")
        git(edge, "commit", "-q", "--no-verify", "-m", "change")
        expect_run("edge cases", docs_check(edge), 1, [
            "docs-check.toml:1: ERROR: line budget for AGENTS.md raised from 10 to 200; budgets only fall",
            "my file.py:2: ERROR: added comment records history: previously",
            "tags.py:1: ERROR: added comment cites a tracker reference: #123",
            "tags.py:2: ERROR: added comment cites a tracker reference: #42",
        ])

    if failures:
        print("docs-check self-test FAILED")
        print("\n".join(failures))
        return 1
    print("docs-check self-test passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
