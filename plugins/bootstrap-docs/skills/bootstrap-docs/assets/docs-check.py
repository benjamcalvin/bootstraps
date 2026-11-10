#!/usr/bin/env python3
import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

if sys.version_info < (3, 11):
    sys.exit(
        "docs-check: Python 3.11 or newer is required (it reads docs-check.toml with tomllib); "
        "found " + sys.version.split()[0]
    )

import tomllib

CONFIG_NAME = "docs-check.toml"
INSTRUCTION_NAMES = ("AGENTS.md", "CLAUDE.md")
NEAR_MISS_NAMES = {"agents.md", "claude.md"}
DEFAULTS = {"default_budget": 200, "covers_churn_lines": 200, "exclude": [], "budgets": {}, "baseline": []}
WALK_SKIP = {".git", "node_modules", ".venv", "venv", "__pycache__", "dist", "build", "vendor", "target"}
BARE_PATH_EXTENSIONS = {
    "md", "mdx", "rst", "txt", "py", "sh", "json", "toml", "yaml", "yml", "cfg", "ini", "lock",
    "sql", "ts", "tsx", "go", "rs", "rb", "java", "kt", "swift", "css", "html",
}
HASH_COMMENT_EXTENSIONS = {
    "py", "sh", "bash", "zsh", "fish", "rb", "pl", "pm", "r", "ps1", "yaml", "yml", "toml",
    "tf", "hcl", "nix", "ex", "exs", "cmake", "mk",
}
HASH_COMMENT_NAMES = {"Makefile", "makefile", "GNUmakefile", "Dockerfile", "Justfile", "justfile", ".gitignore"}
SLASH_COMMENT_EXTENSIONS = {
    "js", "jsx", "mjs", "cjs", "ts", "tsx", "mts", "cts", "go", "rs", "java", "kt", "kts", "swift",
    "c", "h", "cc", "cpp", "cxx", "hpp", "cs", "scala", "dart", "php", "zig", "proto", "groovy", "gradle",
}
DASH_COMMENT_EXTENSIONS = {"sql", "lua", "hs", "elm"}
MISE_CONFIGS = ("mise.toml", ".mise.toml", "mise/config.toml", ".mise/config.toml", ".config/mise.toml", ".config/mise/config.toml")
MISE_TASK_DIRS = ("mise-tasks", ".mise-tasks", "mise/tasks", ".mise/tasks", ".config/mise/tasks")
MAKEFILE_NAMES = ("Makefile", "makefile", "GNUmakefile")

FENCE_RE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
CODE_SPAN_RE = re.compile(r"(`+)(.+?)\1")
LINK_RE = re.compile(r"!?\[[^\]]*\]\(\s*<?([^)\s>]+)>?")
REF_DEF_RE = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*<?([^\s>]+)>?")
HTML_LINK_RE = re.compile(r"""\b(?:href|src)\s*=\s*["']([^"']+)["']""")
SCHEME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")
PATH_SPAN_RE = re.compile(r"^(?:\./)?[A-Za-z0-9_.-][A-Za-z0-9_./-]*$")
PLACEHOLDER_RE = re.compile(r"\b(?:NNN|XXX|YYYY|MM|DD)\b")
BARE_EXTENSION_RE = re.compile(r"^\.[A-Za-z0-9]+$")
EXTENSION_RE = re.compile(r"\.([A-Za-z][A-Za-z0-9]{0,7})$")
CMD_START = r"(?:^|[;&|(]\s*|\$\s+)"
TASK_PATTERNS = (
    ("npm script", re.compile(CMD_START + r"(?:npm|pnpm|yarn|bun)\s+run\s+([A-Za-z0-9_:.-]+)")),
    ("make target", re.compile(CMD_START + r"make\s+(?![\w.-]*=)([A-Za-z0-9_][A-Za-z0-9_./-]*)")),
    ("mise task", re.compile(CMD_START + r"mise\s+(?:run|r|tasks\s+run)\s+([A-Za-z0-9_:./-]+)")),
)
MAKE_RULE_RE = re.compile(r"^([A-Za-z0-9_./ -]+?)\s*::?(?!=)")
IMPORT_RE = re.compile(r"^\s*@\S*AGENTS\.md\s*$")
TODO_REF_RE = re.compile(r"TODO\(#\d+\)")
TRACKER_RE = re.compile(r"(?<![\w&/])#\d+\b")
STEP_RE = re.compile(r"\bstep\s+\d+[a-z]?\s*:", re.IGNORECASE)
HISTORY_RE = re.compile(r"\b(?:previously|no longer|changed from)\b", re.IGNORECASE)
COVERS_RE = re.compile(r"^\s*(?:\*\*Covers:\*\*|Covers:)\s*(.+?)\s*$")
GLOSSARY_RE = re.compile(r"^##\s+Glossary\s*$", re.IGNORECASE)
HEADING2_RE = re.compile(r"^##\s")
TABLE_TERM_RE = re.compile(r"^\s*\|\s*([^|]+?)\s*\|")
LIST_TERM_RE = re.compile(r"^\s*[-*]\s+\*\*(.+?)\*\*")
HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")
BASELINE_ARRAY_RE = re.compile(r'^baseline\s*=\s*\[(?:[^\]"]|"(?:[^"\\]|\\.)*")*\]', re.MULTILINE)
EXEMPT_DOC_RE = re.compile(r"(?:^|/)(?:adr|adrs|decisions)/|(?:^|/)(?:CHANGELOG|CHANGES|HISTORY|RELEASES?)[^/]*$", re.IGNORECASE)


@dataclass
class Violation:
    path: str
    line: int
    severity: str
    message: str
    baselinable: bool = True

    @property
    def key(self):
        return f"{self.path}: {self.message}"

    def render(self):
        return f"{self.path}:{self.line}: {self.severity}: {self.message}"


class UsageError(Exception):
    pass


def run_git(root, *args, stdin=None):
    result = subprocess.run(["git", "-c", "core.quotePath=false", *args], cwd=root, capture_output=True,
                            text=True, encoding="utf-8", errors="replace", input=stdin)
    if result.returncode != 0:
        return None
    return result.stdout


def is_git_repo(root):
    out = run_git(root, "rev-parse", "--is-inside-work-tree")
    return out is not None and out.strip() == "true"


def verify_commit(root, ref):
    out = run_git(root, "rev-parse", "--verify", "--quiet", ref + "^{commit}")
    return out.strip() if out else None


def resolve_base(root, explicit):
    if verify_commit(root, "HEAD") is None:
        if explicit:
            raise UsageError("--base needs a repository with at least one commit")
        return None, None
    if explicit:
        target = verify_commit(root, explicit)
        if target is None:
            raise UsageError(f"--base {explicit} is not a commit")
        label = explicit
    else:
        candidates = []
        origin_head = run_git(root, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
        if origin_head and origin_head.strip():
            candidates.append(origin_head.strip())
        candidates += ["origin/main", "origin/master", "main", "master"]
        target = label = None
        for candidate in candidates:
            target = verify_commit(root, candidate)
            if target:
                label = candidate
                break
        if target is None:
            return None, None
    merge_base = run_git(root, "merge-base", "HEAD", target)
    return (merge_base.strip() if merge_base else target), label


C_ESCAPES = {"a": 7, "b": 8, "t": 9, "n": 10, "v": 11, "f": 12, "r": 13, '"': 34, "\\": 92}


def unquote_c(text):
    out = bytearray()
    index = 0
    while index < len(text):
        char = text[index]
        if char != "\\" or index + 1 >= len(text):
            out += char.encode("utf-8")
            index += 1
            continue
        nxt = text[index + 1]
        if nxt in "01234567":
            digits = re.match(r"[0-7]{1,3}", text[index + 1:]).group(0)
            out.append(int(digits, 8) & 255)
            index += 1 + len(digits)
        else:
            out.append(C_ESCAPES.get(nxt, ord(nxt) & 127))
            index += 2
    return out.decode("utf-8", errors="replace")


def diff_target(header):
    target = header[4:].rstrip("\t")
    if target.startswith('"') and target.endswith('"') and len(target) >= 2:
        target = unquote_c(target[1:-1])
    return target[2:] if target.startswith("b/") else None


def list_files(root, in_git, excludes):
    if in_git:
        out = run_git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard") or ""
        paths = sorted({p for p in out.split("\0") if p and (root / p).is_file()})
    else:
        paths = []
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = sorted(d for d in dirnames if d not in WALK_SKIP)
            for name in filenames:
                paths.append((Path(dirpath) / name).relative_to(root).as_posix())
        paths.sort()
    return [p for p in paths if not any(fnmatch.fnmatchcase(p, pattern) for pattern in excludes)]


def read_text(path):
    try:
        data = path.read_bytes()
    except OSError:
        return None
    if b"\0" in data[:8192] or len(data) > 2_000_000:
        return None
    return data.decode("utf-8", errors="replace")


def exists_exact(root, rel):
    current = root
    for part in [p for p in rel.split("/") if p not in ("", ".")]:
        if part == "..":
            current = current.parent
            continue
        try:
            names = os.listdir(current)
        except OSError:
            return False
        if part not in names:
            return False
        current = current / part
    return True


def load_config(text, source):
    try:
        data = tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise UsageError(f"{source}: invalid TOML: {error}")
    config = {key: (value.copy() if isinstance(value, (dict, list)) else value) for key, value in DEFAULTS.items()}
    config.update(data)
    if not isinstance(config["budgets"], dict) or not all(isinstance(v, int) for v in config["budgets"].values()):
        raise UsageError(f"{source}: [budgets] must map paths to integer line counts")
    for key in ("baseline", "exclude"):
        if not isinstance(config[key], list) or not all(isinstance(v, str) for v in config[key]):
            raise UsageError(f"{source}: {key} must be a list of strings")
    for key in ("default_budget", "covers_churn_lines"):
        if not isinstance(config[key], int):
            raise UsageError(f"{source}: {key} must be an integer")
    config["has_baseline"] = "baseline" in data
    return config


def line_of(text, needle):
    for number, line in enumerate(text.splitlines(), 1):
        if needle in line:
            return number
    return 1


class Doc:
    def __init__(self, path, text):
        self.path = path
        self.lines = text.splitlines()
        self.prose = []
        self.spans = []
        self.code = []
        fence = None
        for number, line in enumerate(self.lines, 1):
            match = FENCE_RE.match(line)
            if fence:
                if match and match.group(1)[0] == fence[0] and len(match.group(1)) >= len(fence):
                    fence = None
                else:
                    self.code.append((number, line))
                continue
            if match:
                fence = match.group(1)
                continue
            for span in CODE_SPAN_RE.finditer(line):
                self.spans.append((number, span.group(2).strip()))
            self.prose.append((number, CODE_SPAN_RE.sub("", line)))


class Checker:
    def __init__(self, root, config, config_rel, network, base, base_label, in_git):
        self.root = root
        self.config_rel = config_rel
        self.config = config
        self.network = network
        self.base = base
        self.base_label = base_label
        self.in_git = in_git
        self.files = list_files(root, in_git, config["exclude"])
        self.file_set = set(self.files)
        self.dir_set = {"/".join(p.split("/")[:i]) for p in self.files for i in range(1, p.count("/") + 1)}
        self.basenames = {p.rsplit("/", 1)[-1] for p in self.files} | {d.rsplit("/", 1)[-1] for d in self.dir_set}
        self.docs = []
        for path in self.files:
            if path.endswith(".md"):
                text = read_text(root / path)
                if text is not None:
                    self.docs.append(Doc(path, text))
        self.violations = []
        self.url_cache = {}
        self.task_names = None
        self.stats = None
        self.over_budget = {}

    def add(self, path, line, severity, message, baselinable=True):
        self.violations.append(Violation(path, line, severity, message, baselinable))

    def run(self):
        for doc in self.docs:
            self.check_links(doc)
            self.check_paths(doc)
            self.check_tasks(doc)
            self.check_doc_history(doc)
            self.check_spec(doc)
        self.check_instruction_files()
        self.check_config_against_base()
        self.check_added_comments()
        return self.violations

    def check_links(self, doc):
        for number, line in doc.prose:
            targets = LINK_RE.findall(line) + HTML_LINK_RE.findall(line)
            match = REF_DEF_RE.match(line)
            if match:
                targets.append(match.group(1))
            for target in targets:
                self.check_target(doc, number, target)

    def check_target(self, doc, number, target):
        if target.startswith("#") or target.startswith("mailto:"):
            return
        if target.startswith("//") or SCHEME_RE.match(target):
            if self.network and target.split(":", 1)[0].lower() in ("http", "https", ""):
                problem = self.check_url(("https:" + target) if target.startswith("//") else target)
                if problem:
                    self.add(doc.path, number, "ERROR", f"external link {problem}: {target}")
            return
        rel = urllib.parse.unquote(target.split("#", 1)[0].split("?", 1)[0])
        if not rel:
            return
        if rel.startswith("/"):
            joined = rel.lstrip("/")
        else:
            joined = os.path.normpath(os.path.join(os.path.dirname(doc.path), rel)).replace(os.sep, "/")
        if joined == ".." or joined.startswith("../"):
            return
        if not exists_exact(self.root, joined):
            self.add(doc.path, number, "ERROR", f"link target does not exist: {target}")

    def check_url(self, url):
        if url in self.url_cache:
            return self.url_cache[url]
        problem = None
        for method in ("HEAD", "GET"):
            request = urllib.request.Request(url, method=method, headers={"User-Agent": "docs-check"})
            try:
                with urllib.request.urlopen(request, timeout=10):
                    problem = None
                break
            except urllib.error.HTTPError as error:
                if error.code == 429:
                    problem = None
                    break
                problem = f"returned HTTP {error.code}"
                if error.code not in (403, 405, 501):
                    break
            except (urllib.error.URLError, OSError, ValueError) as error:
                problem = f"is unreachable ({getattr(error, 'reason', error)})"
                break
        self.url_cache[url] = problem
        return problem

    def check_paths(self, doc):
        doc_dir = os.path.dirname(doc.path)
        unresolved = []
        for number, span in doc.spans:
            if not PATH_SPAN_RE.match(span) or "//" in span or PLACEHOLDER_RE.search(span) or BARE_EXTENSION_RE.match(span):
                continue
            rel = span[2:] if span.startswith("./") else span
            segments = [s for s in rel.rstrip("/").split("/") if s]
            if not segments:
                continue
            extension = EXTENSION_RE.search(segments[-1])
            if len(segments) > 1:
                if not (rel.endswith("/") or extension):
                    continue
            elif not (extension and extension.group(1).lower() in BARE_PATH_EXTENSIONS):
                continue
            if self.path_resolves(doc_dir, rel.rstrip("/"), len(segments) == 1):
                continue
            local = os.path.normpath(os.path.join(doc_dir, rel.rstrip("/"))).replace(os.sep, "/")
            unresolved.append((number, span, [c for c in dict.fromkeys((local, rel.rstrip("/"))) if not c.startswith("../")]))
        ignored = self.ignored_paths({c for _, _, candidates in unresolved for c in candidates})
        for number, span, candidates in unresolved:
            if not ignored.intersection(candidates):
                self.add(doc.path, number, "ERROR", f"backticked path does not exist: {span}")

    def ignored_paths(self, candidates):
        if not self.in_git or not candidates:
            return set()
        out = run_git(self.root, "check-ignore", "-z", "--stdin", stdin="\0".join(sorted(candidates)) + "\0") or ""
        return {p for p in out.split("\0") if p}

    def path_resolves(self, doc_dir, rel, bare):
        local = os.path.normpath(os.path.join(doc_dir, rel)).replace(os.sep, "/")
        for candidate in (local, rel):
            if not candidate.startswith("../") and exists_exact(self.root, candidate):
                return True
        if bare:
            return rel in self.basenames
        suffix = "/" + rel
        return any(p.endswith(suffix) for p in self.files) or any(d.endswith(suffix) for d in self.dir_set)

    def load_tasks(self):
        npm, make, mise = set(), set(), set()
        for path in self.files:
            name = path.rsplit("/", 1)[-1]
            if name == "package.json" and "node_modules/" not in path:
                try:
                    scripts = json.loads(read_text(self.root / path) or "{}").get("scripts", {})
                except (json.JSONDecodeError, AttributeError):
                    scripts = {}
                if isinstance(scripts, dict):
                    npm.update(scripts)
            elif name in MAKEFILE_NAMES:
                for line in (read_text(self.root / path) or "").splitlines():
                    match = MAKE_RULE_RE.match(line)
                    if match and not line.startswith("\t"):
                        make.update(t for t in match.group(1).split() if "%" not in t)
            elif path in MISE_CONFIGS:
                try:
                    tasks = tomllib.loads(read_text(self.root / path) or "").get("tasks", {})
                except tomllib.TOMLDecodeError:
                    tasks = {}
                if isinstance(tasks, dict):
                    mise.update(tasks)
            for task_dir in MISE_TASK_DIRS:
                if path.startswith(task_dir + "/"):
                    task = path[len(task_dir) + 1:].replace("/", ":")
                    mise.update({task, re.sub(r"\.[^.:]+$", "", task)})
        self.task_names = {"npm script": npm, "make target": make, "mise task": mise}

    def check_tasks(self, doc):
        lines = doc.spans + [(number, re.sub(r"\s+#.*$", "", line)) for number, line in doc.code]
        for number, text in lines:
            for kind, pattern in TASK_PATTERNS:
                for match in pattern.finditer(text.strip()):
                    if self.task_names is None:
                        self.load_tasks()
                    if match.group(1) not in self.task_names[kind]:
                        self.add(doc.path, number, "ERROR", f"{kind} not defined: {match.group(1)}")

    def check_doc_history(self, doc):
        if EXEMPT_DOC_RE.search(doc.path):
            return
        for number, line in doc.prose:
            text = TODO_REF_RE.sub("", line)
            match = TRACKER_RE.search(text)
            if match:
                self.add(doc.path, number, "WARNING", f"doc cites an issue number: {match.group(0)}")
            match = HISTORY_RE.search(text)
            if match:
                self.add(doc.path, number, "WARNING", f"doc uses history phrasing: {match.group(0)}")

    def covers_matches(self, entry, path):
        if any(c in entry for c in "*?["):
            return fnmatch.fnmatchcase(path, entry)
        return path == entry.rstrip("/") or path.startswith(entry.rstrip("/") + "/")

    def check_spec(self, doc):
        covers_line, entries = None, []
        for number, line in enumerate(doc.lines, 1):
            match = COVERS_RE.match(line)
            if match:
                covers_line = number
                entries = [e.strip().strip("`").strip() for e in match.group(1).split(",")]
                entries = [e[2:] if e.startswith("./") else e for e in entries if e and "{" not in e]
                break
        if covers_line is None or not entries:
            return
        covered = []
        for entry in entries:
            matched = [p for p in self.files if p != doc.path and self.covers_matches(entry, p)]
            if not matched:
                self.add(doc.path, covers_line, "WARNING", f"Covers path matches no files: {entry}")
            covered += matched
        corpus = "".join(re.sub(r"[^a-z0-9]", "", (read_text(self.root / p) or "").lower()) for p in sorted(set(covered)))
        if covered:
            for number, term in self.glossary_terms(doc):
                normalized = re.sub(r"[^a-z0-9]", "", term.lower())
                if normalized and normalized not in corpus:
                    self.add(doc.path, number, "WARNING", f"glossary term not found in covered code: {term}")
        self.check_churn(doc, covers_line, entries)

    def glossary_terms(self, doc):
        terms, inside = [], False
        for number, line in enumerate(doc.lines, 1):
            if GLOSSARY_RE.match(line):
                inside = True
                continue
            if inside and HEADING2_RE.match(line):
                break
            if not inside:
                continue
            match = TABLE_TERM_RE.match(line) or LIST_TERM_RE.match(line)
            if not match:
                continue
            term = match.group(1).replace("*", "").replace("`", "").strip()
            if not term or set(term) <= set("-: ") or "{" in term or term.lower() == "term":
                continue
            terms.append((number, term))
        return terms

    def numstat(self):
        if self.stats is None:
            self.stats = {}
            if self.base:
                out = run_git(self.root, "diff", "--numstat", "--no-renames", self.base, "--") or ""
                for line in out.splitlines():
                    parts = line.split("\t", 2)
                    if len(parts) == 3 and parts[0].isdigit() and parts[1].isdigit():
                        self.stats[parts[2]] = int(parts[0]) + int(parts[1])
                for path in self.untracked():
                    text = read_text(self.root / path)
                    if text is not None:
                        self.stats[path] = len(text.splitlines())
        return self.stats

    def untracked(self):
        if not self.in_git or not self.base:
            return []
        out = run_git(self.root, "ls-files", "-z", "--others", "--exclude-standard") or ""
        return [p for p in out.split("\0") if p in self.file_set]

    def check_churn(self, doc, covers_line, entries):
        stats = self.numstat()
        if not stats:
            return
        churn = sum(n for path, n in stats.items() if path != doc.path and any(self.covers_matches(e, path) for e in entries))
        if churn >= self.config["covers_churn_lines"] and doc.path not in stats:
            self.add(doc.path, covers_line, "WARNING", f"covered code changed by {churn} lines since {self.base_label} but this spec did not")

    def check_instruction_files(self):
        budgets = self.config["budgets"]
        for path in self.files:
            name = path.rsplit("/", 1)[-1]
            if name.lower() in NEAR_MISS_NAMES and name not in INSTRUCTION_NAMES:
                self.add(path, 1, "ERROR", f"instruction file name is not exact: {name} (use AGENTS.md or CLAUDE.md)")
                continue
            if name not in INSTRUCTION_NAMES:
                continue
            text = read_text(self.root / path) or ""
            lines = text.splitlines()
            if name == "CLAUDE.md" and not any(IMPORT_RE.match(line) for line in lines):
                self.add(path, 1, "ERROR", "CLAUDE.md does not import @AGENTS.md")
            budget = budgets.get(path, self.config["default_budget"])
            if len(lines) > budget:
                self.over_budget[path] = len(lines)
                self.add(path, budget + 1, "ERROR", f"instruction file is {len(lines)} lines, over its {budget}-line budget", False)

    def check_config_against_base(self):
        if not self.base or self.config.get("text") is None:
            return
        old_text = run_git(self.root, "show", f"{self.base}:{self.config_rel}")
        if old_text is None:
            return
        try:
            old = load_config(old_text, f"{self.base_label}:{self.config_rel}")
        except UsageError:
            return
        new, text = self.config, self.config["text"]
        if new["default_budget"] > old["default_budget"]:
            self.add(self.config_rel, line_of(text, "default_budget"), "ERROR",
                     f"default_budget raised from {old['default_budget']} to {new['default_budget']}; budgets only fall", False)
        for path in sorted(set(old["budgets"]) | set(new["budgets"])):
            previous = old["budgets"].get(path, old["default_budget"])
            value = new["budgets"].get(path, new["default_budget"])
            if value > previous:
                line = line_of(text, json.dumps(path)) if path in new["budgets"] else line_of(text, "[budgets]")
                self.add(self.config_rel, line, "ERROR",
                         f"line budget for {path} raised from {previous} to {value}; budgets only fall", False)
        old_entries = set(old["baseline"])
        if old["has_baseline"]:
            for entry in new["baseline"]:
                if entry not in old_entries:
                    self.add(self.config_rel, line_of(text, json.dumps(entry, ensure_ascii=False)[1:-1]), "ERROR",
                             f"baseline entry added: {entry}; the baseline only shrinks", False)

    def comment_marker(self, path):
        name = path.rsplit("/", 1)[-1]
        extension = name.rsplit(".", 1)[-1].lower() if "." in name else ""
        if name in HASH_COMMENT_NAMES or extension in HASH_COMMENT_EXTENSIONS:
            return "#"
        if extension in SLASH_COMMENT_EXTENSIONS:
            return "//"
        if extension in DASH_COMMENT_EXTENSIONS:
            return "--"
        return None

    def comment_text(self, marker, line):
        stripped = line.strip()
        if marker == "//" and stripped.startswith(("/*", "*")):
            return stripped.lstrip("/*").rstrip("*/")
        if stripped.startswith(marker):
            return stripped
        match = re.search(r"(?:^|\s)(" + re.escape(marker) + r"(?!!).*)$", line)
        return match.group(1) if match else None

    def added_lines(self):
        if not self.base:
            return
        out = run_git(self.root, "diff", "-U0", "-M", "--no-color", "--no-ext-diff", self.base, "--") or ""
        path = number = None
        in_header = False
        for line in out.splitlines():
            if line.startswith("diff --git "):
                path, number, in_header = None, None, True
                continue
            if in_header and line.startswith("+++ "):
                path = diff_target(line)
                continue
            match = HUNK_RE.match(line)
            if match:
                number, in_header = int(match.group(1)), False
                continue
            if path and number is not None and line.startswith("+"):
                yield path, number, line[1:]
                number += 1
        for untracked in self.untracked():
            for index, text in enumerate((read_text(self.root / untracked) or "").splitlines(), 1):
                yield untracked, index, text

    def check_added_comments(self):
        checks = (
            (TRACKER_RE, "added comment cites a tracker reference"),
            (STEP_RE, "added comment has a step label"),
            (HISTORY_RE, "added comment records history"),
        )
        for path, number, line in self.added_lines():
            if path not in self.file_set:
                continue
            marker = self.comment_marker(path)
            text = self.comment_text(marker, line) if marker else None
            if text is None:
                continue
            text = TODO_REF_RE.sub("", text)
            for pattern, message in checks:
                match = pattern.search(text)
                if match:
                    self.add(path, number, "ERROR", f"{message}: {match.group(0).strip()}")


def render_baseline(entries):
    if not entries:
        return "baseline = []"
    return "baseline = [\n" + "".join(f"  {json.dumps(e, ensure_ascii=False)},\n" for e in entries) + "]"


def write_baseline(config_path, config, checker):
    current = sorted({v.key for v in checker.violations if v.severity == "ERROR" and v.baselinable})
    text = config["text"]
    if text is None:
        body = [f"default_budget = {config['default_budget']}", f"covers_churn_lines = {config['covers_churn_lines']}",
                "exclude = []", render_baseline(current), "", "[budgets]"]
        body += [f"{json.dumps(path)} = {lines}" for path, lines in sorted(checker.over_budget.items())]
        config_path.write_text("\n".join(body) + "\n")
        return len(current)
    entries = [e for e in config["baseline"] if e in set(current)] if config["has_baseline"] else current
    rendered = render_baseline(entries)
    if BASELINE_ARRAY_RE.search(text):
        text = BASELINE_ARRAY_RE.sub(lambda _: rendered, text, count=1)
    else:
        table = re.search(r"^\[", text, re.MULTILINE)
        position = table.start() if table else len(text)
        prefix = text[:position]
        if prefix and not prefix.endswith("\n"):
            prefix += "\n"
        text = prefix + rendered + "\n" + ("\n" if table else "") + text[position:]
    config_path.write_text(text)
    return len(entries)


def read_config(config_path):
    if not config_path.is_file():
        config = load_config("", config_path.name)
        config["text"] = None
        return config
    text = config_path.read_text()
    config = load_config(text, config_path.name)
    config["text"] = text
    return config


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="docs-check",
        description=(
            "Check a repository's docs for drift. Errors: relative links and backticked paths that do not resolve; "
            "npm, make, and mise tasks named in docs that do not exist; a CLAUDE.md without @AGENTS.md or an "
            "inexactly named instruction file; an instruction file over its line budget, or a budget raised; "
            "comment lines the change adds that cite a tracker (#123), label a step (Step 3:), or record history "
            "(previously, no longer, changed from). Warnings: issue numbers or history phrasing in docs (ADRs and "
            "changelogs exempt); spec glossary terms missing from the code the spec Covers; Covers paths that "
            "changed heavily while the spec did not."
        ),
        epilog=(
            "Output is one 'path:line: SEVERITY: message' per finding. Exit status is 1 when any error is not in "
            "the baseline, 2 on a usage or config error, and 0 otherwise; warnings never change it. "
            "docs-check.toml holds default_budget, [budgets] per instruction file, covers_churn_lines, exclude "
            "globs, and baseline, a list of existing errors that do not fail the run. The baseline only shrinks: "
            "--write-baseline creates the file with every current error, and afterwards only drops entries that "
            "no longer occur."
        ),
    )
    parser.add_argument("--root", type=Path, help="repository root (default: the git top level, else the current directory)")
    parser.add_argument("--config", type=Path, help=f"config file (default: <root>/{CONFIG_NAME})")
    parser.add_argument("--base", help="compare added lines against the merge-base of HEAD and this ref "
                                       "(default: the merge-base with the default branch)")
    parser.add_argument("--network", action="store_true", help="also check external http(s) links over the network; a failing link is an error")
    parser.add_argument("--write-baseline", action="store_true", help="write the current errors to the baseline (it only ever shrinks), then check")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    start = (args.root or Path.cwd()).resolve()
    in_git = is_git_repo(start)
    root = start
    if in_git and args.root is None:
        top = run_git(start, "rev-parse", "--show-toplevel")
        root = Path(top.strip()).resolve() if top else start
    config_path = (args.config or root / CONFIG_NAME).resolve()
    config_rel = config_path.relative_to(root).as_posix() if config_path.is_relative_to(root) else str(config_path)
    try:
        config = read_config(config_path)
        base, base_label = resolve_base(root, args.base) if in_git else (None, None)
    except UsageError as error:
        print(f"docs-check: {error}", file=sys.stderr)
        return 2
    if base is None:
        print("docs-check: no base ref; skipping added-line, budget-history, and churn checks", file=sys.stderr)
    checker = Checker(root, config, config_rel, args.network, base, base_label, in_git)
    checker.run()
    if args.write_baseline:
        count = write_baseline(config_path, config, checker)
        print(f"docs-check: wrote {count} baseline entries to {config_rel}", file=sys.stderr)
        config = read_config(config_path)
        checker = Checker(root, config, config_rel, args.network, base, base_label, in_git)
        checker.run()
    baseline = set(config["baseline"])
    current_keys = {v.key for v in checker.violations}
    reported, baselined = [], 0
    for violation in checker.violations:
        if violation.baselinable and violation.severity == "ERROR" and violation.key in baseline:
            baselined += 1
        else:
            reported.append(violation)
    for entry in config["baseline"]:
        if entry not in current_keys:
            line = line_of(config["text"] or "", json.dumps(entry, ensure_ascii=False)[1:-1])
            reported.append(Violation(config_rel, line, "WARNING",
                                      f"baseline entry no longer occurs; run --write-baseline to drop it: {entry}", False))
    reported.sort(key=lambda v: (v.path, v.line, v.severity, v.message))
    for violation in reported:
        print(violation.render())
    errors = sum(1 for v in reported if v.severity == "ERROR")
    print(f"docs-check: {errors} errors, {len(reported) - errors} warnings, {baselined} baselined", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
