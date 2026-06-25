#!/usr/bin/env python3
"""
Generate or refresh the [Unreleased] scaffold in charts/kasm-helm/CHANGELOG.md.

Default mode: groups commits by inferred category, annotates each entry with
affected components derived from changed file paths.

With --use-llm: runs `helm template` before and after each commit, diffs the
rendered manifests, and submits the result to the Claude Code CLI (`claude -p`)
to generate user-friendly prose entries. Uses Claude Code's existing
authentication — no API key or extra packages required.

Usage:
    python3 scripts/changelog-draft.py [--base BRANCH] [--use-llm] [--model MODEL]
    make changelog
    make changelog-llm
    make changelog-llm CHANGELOG_ARGS="--model claude-sonnet-4-6"
"""
import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CHANGELOG = REPO_ROOT / "charts" / "kasm-helm" / "CHANGELOG.md"
HELM = REPO_ROOT / "bin" / "helm"

DEFAULT_MODEL = "claude-haiku-4-5-20251001"
DIFF_MAX_CHARS = 6000

_SKIP_RE = re.compile(
    r"^(test[s]?:|chore:|ci:|style:|refactor:|wip\b|merge\b)",
    re.IGNORECASE,
)

_CATEGORY_RULES = [
    (re.compile(r"\b(add(ed|s)?|feat(ure)?|new\b)", re.IGNORECASE), "Added"),
    (re.compile(r"\b(fix(ed|es)?|bug|correct(ed)?|resolv)", re.IGNORECASE), "Fixed"),
    (re.compile(r"\b(remov(ed|es)?|drop(ped)?|delet(ed)?|deprecat)", re.IGNORECASE), "Removed"),
    (re.compile(r"\b(security|vuln|cve|patch)\b", re.IGNORECASE), "Security"),
    (re.compile(r"\b(doc[s]?|readme|changelog)\b", re.IGNORECASE), "Documentation"),
]
_DEFAULT_CATEGORY = "Changed"
_CATEGORY_ORDER = ["Added", "Changed", "Fixed", "Removed", "Security", "Documentation"]

_UNRELEASED_RE = re.compile(
    r"^## \[Unreleased\].*?(?=^## \[|\Z)",
    re.MULTILINE | re.DOTALL,
)

_COMPONENT_PATTERNS = [
    (re.compile(r"api[-_]"), "API"),
    (re.compile(r"manager[-_]"), "Manager"),
    (re.compile(r"(?<!rdp[-_])proxy[-_]"), "Proxy"),
    (re.compile(r"guac"), "Guac"),
    (re.compile(r"rdp-https-gateway"), "RDP HTTPS Gateway"),
    (re.compile(r"rdp-gateway"), "RDP Gateway"),
    (re.compile(r"(^|[-_])db[-_]|database"), "Database"),
    (re.compile(r"nginx-shared"), "nginx (shared)"),
]


def _git(*args: str) -> str:
    return subprocess.check_output(["git", *args], text=True).strip()


def _fetch(base: str) -> None:
    try:
        _git("fetch", "origin", base)
    except subprocess.CalledProcessError:
        pass


def _merge_base(base: str) -> str:
    for ref in (f"origin/{base}", base):
        try:
            return _git("merge-base", ref, "HEAD")
        except subprocess.CalledProcessError:
            continue
    sys.exit(f"ERROR: could not determine merge-base with '{base}'")


def _commits(base: str) -> list:
    """Return list of (hash, subject, files) for commits since base."""
    merge_base = _merge_base(base)
    raw = _git("log", "--format=%H\t%s", f"{merge_base}..HEAD")
    result = []
    for line in raw.splitlines():
        if not line.strip():
            continue
        hash_, subject = line.split("\t", 1)
        files_raw = _git("show", "--name-only", "--format=", hash_)
        files = [f for f in files_raw.splitlines() if f.strip()]
        result.append((hash_, subject, files))
    return result


def _infer_components(files: list) -> list:
    found = set()
    for f in files:
        name = Path(f).name.lower()
        for pattern, label in _COMPONENT_PATTERNS:
            if pattern.search(name):
                found.add(label)
    return sorted(found)


def _categorize(subject: str):
    if _SKIP_RE.match(subject):
        return None
    for pattern, category in _CATEGORY_RULES:
        if pattern.search(subject):
            return category
    return _DEFAULT_CATEGORY


def _helm_bin() -> str:
    return str(HELM) if HELM.exists() else "helm"


def _helm_render(chart_path: Path) -> str:
    try:
        return subprocess.check_output(
            [
                _helm_bin(), "template", "kasm-changelog-draft", str(chart_path),
                "-n", "kasm-test",
                "--set", "publicAddr=changelog.example.com",
                "--set", "deploymentSize=small",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def _rendered_diff(hash_: str) -> str:
    """Unified diff of helm template output before and after hash_."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        before_dir = tmp_path / "before"
        after_dir = tmp_path / "after"
        before_dir.mkdir()
        after_dir.mkdir()

        for ref, dest in ((f"{hash_}^", before_dir), (hash_, after_dir)):
            try:
                archive = subprocess.check_output(
                    ["git", "archive", ref, "--", "charts/kasm-helm/"],
                    stderr=subprocess.DEVNULL,
                )
                subprocess.run(
                    ["tar", "-x", "-C", str(dest)],
                    input=archive,
                    check=True,
                    capture_output=True,
                )
            except subprocess.CalledProcessError:
                pass  # first commit on branch has no parent; before stays empty

        before_file = tmp_path / "before.yaml"
        after_file = tmp_path / "after.yaml"
        before_file.write_text(_helm_render(before_dir / "charts" / "kasm-helm"))
        after_file.write_text(_helm_render(after_dir / "charts" / "kasm-helm"))

        result = subprocess.run(
            ["diff", "-u", str(before_file), str(after_file)],
            capture_output=True,
            text=True,
        )
        output = result.stdout
        if len(output) > DIFF_MAX_CHARS:
            output = output[:DIFF_MAX_CHARS] + "\n... (truncated)"
        return output


def _call_llm(subject: str, components: list, files: list, diff: str, model: str) -> str:
    components_str = ", ".join(components) if components else "none detected"
    files_str = "\n".join(f"  {f}" for f in files) or "  (none)"
    diff_str = diff.strip() or "(no rendered diff — chart structure may be unchanged)"

    prompt = f"""You are writing changelog entries for kasm-helm, a Helm chart that deploys Kasm Workspaces on Kubernetes. The audience is Kubernetes operators.

Write a concise, user-friendly changelog entry for the following commit. Focus on what changed and why it matters operationally. Use active voice. Do not mention file names, YAML structure, or internal implementation details unless they are user-facing configuration values (such as values.yaml keys that operators set).

Commit message: {subject}
Components affected: {components_str}
Files changed:
{files_str}

Rendered manifest diff (helm template output before vs after this commit):
{diff_str}

Respond with only the entry text — no leading dash, no markdown, no preamble. 1-2 sentences maximum. If this commit has no user-visible effect (tests, CI, internal tooling only), respond with exactly: SKIP"""

    cmd = ["claude", "-p", prompt, "--model", model]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except FileNotFoundError:
        sys.exit("ERROR: 'claude' not found in PATH. Install Claude Code: https://claude.ai/code")
    except subprocess.CalledProcessError as e:
        sys.exit(f"ERROR: claude exited with code {e.returncode}:\n{e.stderr.strip()}")


def _build_section(commits: list, use_llm: bool, model: str) -> str:
    buckets: dict = {}

    for i, (hash_, subject, files) in enumerate(commits):
        cat = _categorize(subject)
        if cat is None:
            continue

        components = _infer_components(files)

        if use_llm:
            print(f"  [{i + 1}/{len(commits)}] {subject[:70]}", flush=True)
            diff = _rendered_diff(hash_)
            entry = _call_llm(subject, components, files, diff, model)
            if entry == "SKIP":
                print("        → skipped by LLM")
                continue
        else:
            comp_note = f" [{', '.join(components)}]" if components else ""
            entry = f"{subject}{comp_note}"

        buckets.setdefault(cat, []).append(entry)

    if not buckets:
        buckets["Changed"] = ["(no user-facing changes detected — fill in manually)"]

    lines = ["## [Unreleased]\n"]
    for cat in _CATEGORY_ORDER:
        if cat not in buckets:
            continue
        lines.append(f"\n### {cat}\n")
        for entry in buckets[cat]:
            lines.append(f"\n- {entry}")
    lines.append("\n")
    return "".join(lines)


def _update(section: str) -> None:
    text = CHANGELOG.read_text()
    if _UNRELEASED_RE.search(text):
        updated = _UNRELEASED_RE.sub(section, text, count=1)
    else:
        match = re.search(r"\n\n", text)
        insert_at = match.end() if match else len(text)
        updated = text[:insert_at] + section + "\n" + text[insert_at:]
    CHANGELOG.write_text(updated)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", default="develop", metavar="BRANCH", help="Base branch to diff against (default: develop)")
    parser.add_argument("--use-llm", action="store_true", help="Use Claude Code CLI with rendered diffs to generate prose entries (requires `claude` in PATH)")
    parser.add_argument("--model", default=DEFAULT_MODEL, metavar="MODEL", help=f"Claude model for --use-llm (default: {DEFAULT_MODEL})")
    parser.add_argument("--dry-run", action="store_true", help="Print the generated section to stdout instead of writing to CHANGELOG.md")
    args = parser.parse_args()

    _fetch(args.base)
    commits = _commits(args.base)

    if not commits:
        print(f"No commits found since '{args.base}'. Nothing to scaffold.")
        return

    if args.use_llm:
        print(f"Generating entries with {args.model} ({len(commits)} commit(s), rendered diff per commit)...")

    section = _build_section(commits, args.use_llm, args.model)

    if args.dry_run:
        print(section)
        return

    _update(section)

    skipped = sum(1 for _, s, _ in commits if _categorize(s) is None)
    included = len(commits) - skipped
    mode = "LLM-generated" if args.use_llm else "scaffold"
    print(f"Wrote {included} {mode} entr{'y' if included == 1 else 'ies'} to {CHANGELOG} ({skipped} internal skipped).")
    if not args.use_llm:
        print("Edit the [Unreleased] entries to user-friendly language, then commit.")


if __name__ == "__main__":
    main()
