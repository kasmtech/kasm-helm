#!/usr/bin/env python3
"""
Generate or refresh the [Unreleased] section in each chart's CHANGELOG.md.

A commit's entry is routed to every chart under charts/<chart>/ whose files
that commit touches. Commits that touch no charts/ path are skipped
entirely. A commit touching multiple charts gets an entry in each.

Default mode: groups commits by inferred category, annotates each entry with
affected components derived from changed file paths.

With --use-llm: runs `helm template` before and after each commit (per
affected chart), diffs the rendered manifests, and submits the result to the
Claude Code CLI (`claude -p`) to generate user-friendly prose entries. Uses
Claude Code's existing authentication — no API key or extra packages
required. Library charts (type: library) produce no rendered manifests, so
they get an empty diff and rely on the file-list context only.

Additive by design: each entry is stamped with its commit hash in an HTML
comment (invisible in rendered markdown). Re-running the script only adds
entries for commits not already represented, so edits to existing entries are
preserved across runs.

Usage:
    python3 scripts/changelog-draft.py [--base BRANCH] [--use-llm] [--model MODEL] [--dry-run]
    make changelog
    make changelog-llm
    make changelog-llm CHANGELOG_ARGS="--model claude-sonnet-4-6"
    make changelog-console
"""
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CHARTS_DIR = REPO_ROOT / "charts"
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

# Matches any existing leading "# Changelog" title and subtitle line so it
# can be stripped before the canonical (chart-specific) header is prepended.
# The subtitle names whichever chart the file already belongs to.
_LEADING_HEADER_RE = re.compile(
    r"^\s*# Changelog\s*\n+"
    r"(?:All notable changes to the [\w.-]+ chart are documented here\.\s*\n+)?",
)

# Embedded hash marker written into every entry; invisible in rendered markdown.
_HASH_RE = re.compile(r"<!-- hash:([0-9a-f]+) -->")

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


def _header_text(chart: str) -> str:
    """Canonical top-of-file header for a given chart's CHANGELOG.md."""
    return (
        "# Changelog\n"
        "\n"
        f"All notable changes to the {chart} chart are documented here.\n"
        "\n"
    )


def _ensure_header(text: str, chart: str) -> str:
    """Return text with the canonical header guaranteed at the top."""
    stripped = _LEADING_HEADER_RE.sub("", text, count=1)
    return _header_text(chart) + stripped.lstrip("\n")


# ---------------------------------------------------------------------------
# Chart discovery and per-chart paths
# ---------------------------------------------------------------------------

def _discover_charts() -> list:
    """Return sorted chart names: subdirectories of charts/ with a Chart.yaml."""
    return sorted(
        p.name for p in CHARTS_DIR.iterdir()
        if p.is_dir() and (p / "Chart.yaml").exists()
    )


def _changelog_path(chart: str) -> Path:
    return CHARTS_DIR / chart / "CHANGELOG.md"


def _is_library_chart(chart: str) -> bool:
    """Library charts (type: library) render no manifests; skip helm diffing."""
    chart_yaml = CHARTS_DIR / chart / "Chart.yaml"
    if not chart_yaml.exists():
        return False
    return bool(re.search(r"^type:\s*library\b", chart_yaml.read_text(), re.MULTILINE))


# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

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
    """Return [(hash, subject, files)] for commits since base."""
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


# ---------------------------------------------------------------------------
# Categorisation and component inference
# ---------------------------------------------------------------------------

def _categorize(subject: str):
    if _SKIP_RE.match(subject):
        return None
    for pattern, category in _CATEGORY_RULES:
        if pattern.search(subject):
            return category
    return _DEFAULT_CATEGORY


def _infer_components(files: list) -> list:
    found = set()
    for f in files:
        name = Path(f).name.lower()
        for pattern, label in _COMPONENT_PATTERNS:
            if pattern.search(name):
                found.add(label)
    return sorted(found)


# ---------------------------------------------------------------------------
# Helm rendering and diff
# ---------------------------------------------------------------------------

def _helm_bin() -> str:
    return str(HELM) if HELM.exists() else "helm"


_HELM_SET_FLAGS = {
    "kasm-helm": [
        "--set", "publicAddr=changelog.example.com",
        "--set", "deploymentSize=small",
    ],
    "kasm-otel-router": [
        "--set", "registrations[0].namespace=kasm-example",
        "--set", "registrations[0].endpoint=otel-gateway.kasm-example.svc.cluster.local:4317",
        "--set", "registrations[0].tokenSecret.name=kasm-example-secrets",
        "--set", "registrations[0].tokenSecret.key=otel-bearer-token",
    ],
}

# Sentinel returned by _rendered_diff when `helm template` itself failed (e.g. a chart's
# required-value guards reject the flags in _HELM_SET_FLAGS) — distinct from a real, empty diff.
RENDER_FAILED = "\x00RENDER_FAILED\x00"


def _helm_render(chart_path: Path, chart: str) -> str:
    if not chart_path.exists():
        return ""  # e.g. the "before" side of a chart's first commit
    try:
        return subprocess.check_output(
            [
                _helm_bin(), "template", "kasm-changelog-draft", str(chart_path),
                "-n", "kasm-test",
                *_HELM_SET_FLAGS.get(chart, []),
            ],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return RENDER_FAILED


def _rendered_diff(hash_: str, chart: str) -> str:
    """Unified diff of helm template output before and after hash_ for chart.

    Returns RENDER_FAILED if either side's `helm template` call errored out, so
    callers can tell a failed render apart from a genuinely unchanged/empty diff.
    """
    if _is_library_chart(chart):
        return ""

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        before_dir = tmp_path / "before"
        after_dir = tmp_path / "after"
        before_dir.mkdir()
        after_dir.mkdir()

        for ref, dest in ((f"{hash_}^", before_dir), (hash_, after_dir)):
            try:
                archive = subprocess.check_output(
                    ["git", "archive", ref, "--", f"charts/{chart}/"],
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

            # ponytail: charts/<chart>/charts/*.tgz (helm dependency build output) is
            # gitignored, so `git archive` never includes it and `helm template` fails
            # dependency resolution. Vendor from the live checkout instead of re-fetching
            # per-ref; fine for a changelog diff tool, upgrade to `helm dep build` per-ref
            # if a dependency's contents ever need to match the historical commit exactly.
            live_dep_dir = CHARTS_DIR / chart / "charts"
            if live_dep_dir.is_dir():
                archived_chart_dir = dest / "charts" / chart
                if archived_chart_dir.is_dir():
                    dep_dest = archived_chart_dir / "charts"
                    dep_dest.mkdir(exist_ok=True)
                    for tgz in live_dep_dir.glob("*.tgz"):
                        shutil.copy(tgz, dep_dest / tgz.name)

        before_rendered = _helm_render(before_dir / "charts" / chart, chart)
        after_rendered = _helm_render(after_dir / "charts" / chart, chart)
        if before_rendered is RENDER_FAILED or after_rendered is RENDER_FAILED:
            return RENDER_FAILED

        before_file = tmp_path / "before.yaml"
        after_file = tmp_path / "after.yaml"
        before_file.write_text(before_rendered)
        after_file.write_text(after_rendered)

        result = subprocess.run(
            ["diff", "-u", str(before_file), str(after_file)],
            capture_output=True,
            text=True,
        )
        output = result.stdout
        if len(output) > DIFF_MAX_CHARS:
            output = output[:DIFF_MAX_CHARS] + "\n... (truncated)"
        return output


# ---------------------------------------------------------------------------
# LLM call
# ---------------------------------------------------------------------------

def _call_llm(chart: str, subject: str, components: list, files: list, diff: str, model: str) -> str:
    components_str = ", ".join(components) if components else "none detected"
    files_str = "\n".join(f"  {f}" for f in files) or "  (none)"
    if diff == RENDER_FAILED:
        diff_str = "(helm render failed — describe from commit message and files only)"
    else:
        diff_str = diff.strip() or "(no rendered diff — chart structure may be unchanged)"

    prompt = f"""You are writing changelog entries for {chart}, a Helm chart that deploys Kasm Workspaces on Kubernetes. The audience is Kubernetes operators.

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


# ---------------------------------------------------------------------------
# Hash tracking — keeps runs additive
# ---------------------------------------------------------------------------

def _extract_hashes(text: str) -> set:
    """Return all commit hashes embedded in an existing changelog section."""
    return set(_HASH_RE.findall(text))


def _stamp(entry: str, hash_: str) -> str:
    """Append an invisible hash marker to an entry line."""
    return f"{entry} <!-- hash:{hash_} -->"


# ---------------------------------------------------------------------------
# Section building and merging
# ---------------------------------------------------------------------------

def _build_new_entries(chart: str, commits: list, use_llm: bool, model: str) -> dict:
    """Return {category: [stamped_entry_string]} for the given commits.

    `commits` entries carry only the files under this chart's own path.
    """
    buckets: dict = {}

    for i, (hash_, subject, files) in enumerate(commits):
        cat = _categorize(subject)
        if cat is None:
            continue

        components = _infer_components(files)

        if use_llm:
            print(f"  [{chart}] [{i + 1}/{len(commits)}] {subject[:70]}", flush=True)
            diff = _rendered_diff(hash_, chart)
            text = _call_llm(chart, subject, components, files, diff, model)
            if text == "SKIP":
                print("        → skipped by LLM")
                continue
        else:
            comp_note = f" [{', '.join(components)}]" if components else ""
            text = f"{subject}{comp_note}"

        buckets.setdefault(cat, []).append(_stamp(text, hash_))

    return buckets


def _render_fresh_section(buckets: dict) -> str:
    """Render a complete new [Unreleased] section from a buckets dict."""
    if not buckets:
        buckets = {"Changed": [_stamp("(no user-facing changes detected — fill in manually)", "000000")]}

    lines = ["## [Unreleased]\n"]
    for cat in _CATEGORY_ORDER:
        if cat not in buckets:
            continue
        lines.append(f"\n### {cat}\n\n")
        for entry in buckets[cat]:
            lines.append(f"- {entry}\n")
    return "".join(lines)


def _merge_into_existing(existing: str, new_buckets: dict) -> str:
    """
    Insert new entries into an existing [Unreleased] section, preserving all
    existing text. New entries for existing categories are appended within that
    category block; new categories are appended at the end of the section.
    """
    result = existing.rstrip("\n")

    for cat in _CATEGORY_ORDER:
        if cat not in new_buckets:
            continue

        header = f"### {cat}"
        entries_text = "".join(f"- {e}\n" for e in new_buckets[cat])

        if header in result:
            # Find where the next category header (or end of section) begins
            # and insert the new entries just before it.
            cat_start = result.index(header) + len(header)
            next_header = re.search(r"\n### ", result[cat_start:])
            if next_header:
                insert_at = cat_start + next_header.start()
            else:
                insert_at = len(result)
            result = result[:insert_at] + entries_text + result[insert_at:]
        else:
            result += f"\n\n{header}\n\n{entries_text}"

    return result + "\n"


# ---------------------------------------------------------------------------
# Changelog file update
# ---------------------------------------------------------------------------

def _update(chart: str, new_buckets: dict) -> bool:
    """
    Write new_buckets into the given chart's CHANGELOG.md, creating the file
    (with just the canonical header) if it does not already exist.

    Returns existing_had_unreleased for reporting.
    """
    path = _changelog_path(chart)
    existing = path.read_text() if path.exists() else ""
    text = _ensure_header(existing, chart)
    match = _UNRELEASED_RE.search(text)

    if match:
        merged = _merge_into_existing(match.group(0), new_buckets)
        updated = text[:match.start()] + merged + text[match.end():]
        had_unreleased = True
    else:
        fresh = _render_fresh_section(new_buckets)
        insert_at = len(_header_text(chart))
        updated = text[:insert_at] + fresh + "\n" + text[insert_at:]
        had_unreleased = False

    path.write_text(updated)
    return had_unreleased


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--base", default="develop", metavar="BRANCH",
        help="Base branch to diff against (default: develop)",
    )
    parser.add_argument(
        "--use-llm", action="store_true",
        help="Use Claude Code CLI with rendered diffs to generate prose entries (requires `claude` in PATH)",
    )
    parser.add_argument(
        "--model", default=DEFAULT_MODEL, metavar="MODEL",
        help=f"Claude model for --use-llm (default: {DEFAULT_MODEL})",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print new entries to stdout instead of writing to CHANGELOG.md",
    )
    args = parser.parse_args()

    _fetch(args.base)
    all_commits = _commits(args.base)

    def _status(msg: str) -> None:
        print(msg, file=sys.stderr)

    if not all_commits:
        _status(f"No commits found since '{args.base}'. Nothing to add.")
        return

    charts = _discover_charts()
    any_chart_touched = False
    total_included = 0

    for chart in charts:
        prefix = f"charts/{chart}/"
        path = _changelog_path(chart)
        existing_text = path.read_text() if path.exists() else ""
        existing_match = _UNRELEASED_RE.search(existing_text)
        already_seen = _extract_hashes(existing_match.group(0)) if existing_match else set()

        chart_commits = []
        for h, s, f in all_commits:
            if h in already_seen:
                continue
            chart_files = [fp for fp in f if fp.startswith(prefix)]
            if not chart_files:
                continue
            chart_commits.append((h, s, chart_files))

        if not chart_commits:
            continue

        any_chart_touched = True
        if already_seen:
            _status(f"[{chart}] {len(already_seen)} existing commit(s) in [Unreleased]; processing {len(chart_commits)} new.")

        if args.use_llm:
            _status(f"[{chart}] Generating entries with {args.model} ({len(chart_commits)} commit(s), rendered diff per commit)...")

        new_buckets = _build_new_entries(chart, chart_commits, args.use_llm, args.model)

        if args.dry_run:
            if not new_buckets:
                continue
            text = _ensure_header(existing_text, chart)
            match = _UNRELEASED_RE.search(text)
            if match:
                merged = _merge_into_existing(match.group(0), new_buckets)
                out = text[:match.start()] + merged + text[match.end():]
            else:
                fresh = _render_fresh_section(new_buckets)
                insert_at = len(_header_text(chart))
                out = text[:insert_at] + fresh + "\n" + text[insert_at:]
            print(f"=== {path.relative_to(REPO_ROOT)} ===")
            sys.stdout.write(out)
            continue

        _update(chart, new_buckets)
        skipped = sum(1 for _, s, _ in chart_commits if _categorize(s) is None)
        included = len(chart_commits) - skipped
        total_included += included
        mode = "LLM-generated" if args.use_llm else "scaffold"
        _status(f"[{chart}] Added {included} {mode} entr{'y' if included == 1 else 'ies'} to {path} ({skipped} internal skipped).")

    if not any_chart_touched:
        _status(f"All {len(all_commits)} commit(s) already represented or touch no chart. Nothing to add.")
        return

    if not args.dry_run and not args.use_llm and total_included:
        _status("Edit the [Unreleased] entries to user-friendly language, then commit.")


if __name__ == "__main__":
    main()
