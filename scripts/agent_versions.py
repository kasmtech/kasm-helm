#!/usr/bin/env python3
"""Keep the agent-family charts' ``file://`` dependency pins in lockstep.

charts/kasm-helm is versioned on the Kasm Workspaces release line, and
scripts/set_versions.py drives that coupling (chart version -> app version ->
README badges -> useImageTags).  The agent-family charts are different: they are
hand-versioned, all currently 1.1200.0-develop with appVersion "develop" -- aligned
to kasm-helm's release line, but nothing *derives* one from another the way
set_versions.py drives kasm-helm.  What couples *them* is Helm's ``file://``
dependency mechanism:

  charts/kasm-agent      pins six local subcharts by exact version
                         (operator, otel-collector, agent-instance, node-prep,
                         video-device-plugin, egress-installer)
  charts/kasm-platform   pins charts/kasm-helm and charts/kasm-agent the same way

Every one of those pins is maintained by hand, and the failure mode is
asymmetric.  Bumping a subchart's own version without bumping the parent's pin
makes ``helm dependency build`` fail loudly (``can't get a valid version for
dependency <name>``) -- but only because it re-resolves.  ``helm package`` run
against a chart directory whose ``charts/`` is already staged does not
re-resolve: it exits 0 and embeds the *stale* archive, so the published umbrella
silently ships the subchart the release was supposed to replace.  ``helm lint``
passes too.  That is the gap this script closes, and it is not hypothetical --
the highest-frequency case is charts/kasm-helm, whose version
scripts/set_versions.py bumps on every release without touching the
charts/kasm-platform pin that names it.

A second, non-dependency coupling is checked alongside it: charts/kasm-agent-crds
ships the same five CustomResourceDefinitions charts/kasm-agent-operator carries
in crds/ (``make crds-sync-check`` guards their *content*).  Two charts shipping
one schema set have to carry one version, or "which CRD release am I on" has two
answers.

Usage:
    python3 scripts/agent_versions.py --check
    python3 scripts/agent_versions.py --bump kasm-agent-instance 1.1201.0-develop
    python3 scripts/agent_versions.py --bump kasm-agent-instance 1.1201.0-develop --write
    python3 scripts/agent_versions.py --align            # every agent-family chart
    python3 scripts/agent_versions.py --align --write    #   to kasm-helm's version

``--bump`` rewrites the named chart's own ``version:`` *and* every parent pin
that references it, so the two never drift apart in the first place.  ``--align``
does the same for every agent-family chart at once, setting each to whatever
version charts/kasm-helm currently declares (kasm-helm's own version stays
set_versions.py's; its pin in charts/kasm-platform is aligned like any other).
That is the release-bump path: run it right after set_versions.py moves
kasm-helm, or via ``make set-version CHART_VERSION=...`` which chains both plus
the README and dependency-archive refresh.  Both modes are a dry run until
``--write`` is given.

Pure stdlib, and deliberately line-based rather than YAML-round-tripped: these
Chart.yaml files carry a lot of explanatory comment, every edit here is a
single ``version:`` line, and the line numbers are what the dry-run report
prints.
"""
import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CHARTS_ROOT = REPO_ROOT / "charts"

# charts/kasm-agent-crds re-ships charts/kasm-agent-operator's CRDs as ordinary
# templates.  Neither depends on the other, so no ``file://`` pin ties their
# versions together -- this list does.  (Content parity is `make crds-sync-check`.)
VERSION_PARITY_PAIRS = [("kasm-agent-crds", "kasm-agent-operator")]

# Helm requires SemVer 2 chart versions.  The leading ``v`` is tolerated because
# Helm itself tolerates it (charts/kasm-agent's gpu-operator pin is ``v26.7.0``),
# but nothing in this repo's own charts uses it.
SEMVER_RE = re.compile(
    r"^v?(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
    r"(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"
)

FILE_REPO_PREFIX = "file://"

# charts/kasm-helm's own version is not ours to move: scripts/set_versions.py owns
# it, because bumping it also derives appVersion, rewrites the root README badges
# and install snippets, and resets values.yaml's useImageTags.  Its *pin* in
# charts/kasm-platform is ours, and that is the edit the realistic flow needs --
# `make readme CHART_VERSION=...` moves the chart, then --bump here catches the pin
# up (the chart's own version line is already correct by then, so it is skipped).
EXTERNALLY_VERSIONED_CHARTS = {"kasm-helm": "scripts/set_versions.py (make readme CHART_VERSION=...)"}


class ChartError(Exception):
    pass


# --------------------------------------------------------------------------
# Chart.yaml parsing
# --------------------------------------------------------------------------


class Chart:
    """One chart directory, with the line number of its top-level ``version:``."""

    def __init__(self, directory: Path):
        self.dir = directory
        self.chart_yaml = directory / "Chart.yaml"
        self.lines = self.chart_yaml.read_text(encoding="utf-8").splitlines()
        self.name = self._scalar("name")
        self.version, self.version_line = self._scalar_with_line("version")
        self.dependencies = self._parse_dependencies()

    # `name:` / `version:` at column 0 -- an indented `version:` belongs to a
    # dependency entry, and `appVersion:` is a different key entirely.
    def _scalar_with_line(self, key: str) -> tuple[str, int]:
        pattern = re.compile(rf"^{re.escape(key)}:\s*(.*)$")
        hits = [(i, pattern.match(line)) for i, line in enumerate(self.lines, start=1)]
        hits = [(i, m.group(1).strip()) for i, m in hits if m]
        if len(hits) != 1:
            raise ChartError(
                f"{self.chart_yaml}: expected exactly one top-level '{key}:' line, found {len(hits)}"
            )
        line_no, raw = hits[0]
        return unquote(raw), line_no

    def _scalar(self, key: str) -> str:
        return self._scalar_with_line(key)[0]

    def _parse_dependencies(self) -> list["Dependency"]:
        deps: list[Dependency] = []
        in_block = False
        current: dict | None = None
        for line_no, line in enumerate(self.lines, start=1):
            if re.match(r"^dependencies:\s*$", line):
                in_block = True
                continue
            if not in_block:
                continue
            # Any other column-0 key ends the block.
            if line.strip() and not line[0].isspace():
                break
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            item = re.match(r"^(\s*)-\s+(.*)$", line)
            if item:
                current = {"_lines": {}}
                deps.append(current)  # type: ignore[arg-type]
                stripped = item.group(2)
            if current is None:
                continue
            kv = re.match(r"^([A-Za-z0-9_.-]+):\s*(.*)$", stripped)
            if kv:
                current[kv.group(1)] = unquote(kv.group(2).strip())
                current["_lines"][kv.group(1)] = line_no
        return [Dependency(self, raw) for raw in deps]  # type: ignore[arg-type]

    def local_dependencies(self) -> list["Dependency"]:
        return [d for d in self.dependencies if d.is_local]

    def write(self) -> None:
        self.chart_yaml.write_text("\n".join(self.lines) + "\n", encoding="utf-8")


class Dependency:
    def __init__(self, parent: Chart, raw: dict):
        self.parent = parent
        self.name = raw.get("name", "<unnamed>")
        self.version = raw.get("version", "")
        self.repository = raw.get("repository", "")
        self.version_line = raw.get("_lines", {}).get("version", 0)
        self.is_local = self.repository.startswith(FILE_REPO_PREFIX)

    @property
    def target_dir(self) -> Path:
        """The chart directory a ``file://`` repository points at."""
        rel = self.repository[len(FILE_REPO_PREFIX) :]
        return (self.parent.dir / rel).resolve()


def unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def replace_scalar(line: str, new_value: str) -> str:
    """Rewrite ``<indent>key: <old>`` in place, preserving indent and quoting."""
    m = re.match(r"^(\s*(?:-\s+)?[A-Za-z0-9_.-]+:\s*)(.*)$", line)
    if not m:
        raise ChartError(f"cannot rewrite version line: {line!r}")
    prefix, old = m.group(1), m.group(2).strip()
    quote = old[0] if len(old) >= 2 and old[0] == old[-1] and old[0] in "\"'" else ""
    return f"{prefix}{quote}{new_value}{quote}"


def load_charts() -> dict[str, Chart]:
    charts: dict[str, Chart] = {}
    for chart_yaml in sorted(CHARTS_ROOT.glob("*/Chart.yaml")):
        chart = Chart(chart_yaml.parent)
        charts[chart.name] = chart
    if not charts:
        raise ChartError(f"no charts found under {CHARTS_ROOT}")
    return charts


# --------------------------------------------------------------------------
# --check
# --------------------------------------------------------------------------


class Row:
    """One place two versions have to agree.

    ``kind`` is "pin" (a parent's ``file://`` dependency version vs. the version
    the referenced chart declares) or "parity" (two independent charts that must
    carry one version because they ship one thing).
    """

    def __init__(self, kind: str, site: str, subject: str, found: str, expected: str,
                 note: str = "", peer: str = ""):
        self.kind = kind
        self.site = site
        self.subject = subject
        self.found = found
        self.expected = expected
        self.note = note
        # For a parity row, the chart on the other side of the "must equal".
        self.peer = peer or subject
        self.ok = found == expected and not note

    def describe_failure(self) -> str:
        if self.note:
            return f"{self.site}: {self.subject} -- {self.note}"
        if self.kind == "parity":
            return (
                f"charts/{self.subject} is {self.found} but charts/{self.peer} is "
                f"{self.expected}; both ship the same CRD schemas and must carry one version."
            )
        return (
            f"charts/{self.site}/Chart.yaml pins {self.subject} at {self.found}, but "
            f"charts/{self.subject}/Chart.yaml declares {self.expected}."
        )


def collect_rows(charts: dict[str, Chart]) -> list[Row]:
    rows: list[Row] = []
    for chart in sorted(charts.values(), key=lambda c: c.name):
        for dep in chart.local_dependencies():
            target = dep.target_dir
            referenced = next((c for c in charts.values() if c.dir.resolve() == target), None)
            if referenced is None:
                rows.append(
                    Row("pin", chart.name, dep.name, dep.version, "?",
                        f"repository {dep.repository} does not resolve to a chart directory")
                )
                continue
            if referenced.name != dep.name:
                rows.append(
                    Row("pin", chart.name, dep.name, dep.version, referenced.version,
                        f"repository {dep.repository} points at chart '{referenced.name}'")
                )
                continue
            rows.append(Row("pin", chart.name, dep.name, dep.version, referenced.version))

    for shipper, source in VERSION_PARITY_PAIRS:
        if shipper in charts and source in charts:
            rows.append(
                Row("parity", f"= {source}", shipper,
                    charts[shipper].version, charts[source].version, peer=source)
            )
    return rows


def print_table(rows: list[Row]) -> None:
    headers = ("site", "chart", "version", "must equal")
    cells = [
        (f"pin in {r.site}" if r.kind == "pin" else "version parity", r.subject, r.found, r.expected)
        for r in rows
    ]
    widths = [max(len(headers[i]), *(len(c[i]) for c in cells)) for i in range(4)]
    fmt = "  " + "  ".join(f"{{:<{w}}}" for w in widths) + "  {}"
    print(fmt.format(*headers, "").rstrip())
    print("  " + "  ".join("-" * w for w in widths))
    for row, cell in zip(rows, cells):
        status = "ok" if row.ok else "MISMATCH"
        if row.kind == "parity":
            status += f"   ({row.site}: same CRDs, see crds-sync-check)"
        print(fmt.format(*cell, status).rstrip())


def check() -> int:
    charts = load_charts()
    rows = collect_rows(charts)
    if not rows:
        print("No file:// dependency pins and no version-parity pairs to check.")
        return 0
    bad = [r for r in rows if not r.ok]

    print("Agent-family chart versions (file:// dependency pins + CRD version parity):")
    print("")
    print_table(rows)
    print("")

    if not bad:
        print(f"OK: all {len(rows)} version couplings agree.")
        return 0

    print(f"ERROR: {len(bad)} of {len(rows)} version couplings disagree.")
    print("")
    for row in bad:
        print(f"  {row.describe_failure()}")
    print("")
    print(
        "A stale pin is not always loud.  `helm dependency build` refuses it, but\n"
        "`helm package` against an already-staged charts/ directory exits 0 and embeds\n"
        "the OLD subchart archive -- so the published umbrella ships the dependency the\n"
        "release was meant to replace, and `helm lint` passes."
    )
    print("")
    print("Fix each one in a single step -- --bump moves the chart AND every pin naming it:")
    for row in bad:
        if row.expected == "?":
            print(f"  # {row.site}: fix the repository path by hand")
            continue
        target, version = (row.subject, row.expected)
        if row.kind == "parity":
            print(
                f"  python3 scripts/agent_versions.py --bump {target} <intended> --write"
                f"   # moves {target} and {row.peer} together"
            )
            continue
        print(f"  python3 scripts/agent_versions.py --bump {target} {version} --write")
    print("  ./bin/helm dependency update charts/kasm-agent charts/kasm-platform")
    return 1


# --------------------------------------------------------------------------
# --bump
# --------------------------------------------------------------------------


class Edit:
    def __init__(self, path: Path, line_no: int, before: str, after: str, why: str):
        self.path = path
        self.line_no = line_no
        self.before = before
        self.after = after
        self.why = why


def plan_bump(charts: dict[str, Chart], chart_name: str, new_version: str) -> list[Edit]:
    if chart_name not in charts:
        known = ", ".join(sorted(charts))
        raise ChartError(f"unknown chart {chart_name!r}; known charts: {known}")
    if not SEMVER_RE.match(new_version):
        raise ChartError(f"{new_version!r} is not a SemVer 2 version (Helm requires MAJOR.MINOR.PATCH)")

    # Charts whose own version this bump moves.  Normally just the one named;
    # the CRD parity pair moves together, because a version they do not share is
    # a --check failure the moment either one alone is bumped.
    targets = [chart_name]
    for shipper, source in VERSION_PARITY_PAIRS:
        if chart_name in (shipper, source):
            partner = source if chart_name == shipper else shipper
            if partner in charts and partner not in targets:
                targets.append(partner)

    edits: list[Edit] = []
    for target in targets:
        chart = charts[target]
        why = (
            f"{target}'s own version"
            if target == chart_name
            else f"{target}'s own version (kept equal to {chart_name}: both ship the same CRDs)"
        )
        if chart.version == new_version:
            continue
        if target in EXTERNALLY_VERSIONED_CHARTS:
            raise ChartError(
                f"{target} is at {chart.version}; its own version is owned by "
                f"{EXTERNALLY_VERSIONED_CHARTS[target]}, not by this script.\n"
                f"       Bump it there first, then re-run this --bump to catch the "
                f"charts/kasm-platform pin up."
            )
        edits.append(
            Edit(chart.chart_yaml, chart.version_line,
                 chart.lines[chart.version_line - 1],
                 replace_scalar(chart.lines[chart.version_line - 1], new_version),
                 why)
        )

    # Every file:// pin naming any of those charts.
    for parent in sorted(charts.values(), key=lambda c: c.name):
        for dep in parent.local_dependencies():
            if dep.name not in targets or dep.version == new_version:
                continue
            edits.append(
                Edit(parent.chart_yaml, dep.version_line,
                     parent.lines[dep.version_line - 1],
                     replace_scalar(parent.lines[dep.version_line - 1], new_version),
                     f"{parent.name}'s pin on {dep.name}")
            )
    return edits


def bump(chart_name: str, new_version: str, write: bool) -> int:
    charts = load_charts()
    edits = plan_bump(charts, chart_name, new_version)

    if not edits:
        print(f"Nothing to do: {chart_name} and every pin on it are already at {new_version}.")
        return 0

    verb = "Applying" if write else "Would apply"
    print(f"{verb} {len(edits)} edit(s) to set {chart_name} to {new_version}:")
    print("")
    for edit in edits:
        rel = edit.path.relative_to(REPO_ROOT)
        print(f"  {rel}:{edit.line_no}  ({edit.why})")
        print(f"    - {edit.before.strip()}")
        print(f"    + {edit.after.strip()}")
    print("")

    if not write:
        print("Dry run -- nothing written.  Re-run with --write to apply.")
        return 0

    # Group by file so each Chart.yaml is rewritten once, from the in-memory
    # line list every edit for that file has already been staged into.
    for edit in edits:
        chart = next(c for c in charts.values() if c.chart_yaml == edit.path)
        chart.lines[edit.line_no - 1] = edit.after
    for path in dict.fromkeys(e.path for e in edits):
        next(c for c in charts.values() if c.chart_yaml == path).write()

    print(f"Wrote {len({e.path for e in edits})} Chart.yaml file(s).")
    print("")
    print("Next: refresh the lock files, which still name the old version --")
    print("  ./bin/helm dependency update charts/kasm-agent")
    print("  ./bin/helm dependency update charts/kasm-platform")
    print("and note the bump in the affected charts' CHANGELOG.md (make changelog-check-all).")
    return 0


# --------------------------------------------------------------------------
# --align
# --------------------------------------------------------------------------


def plan_align(charts: dict[str, Chart]) -> tuple[str, list[Edit]]:
    """Every agent-family chart, and every file:// pin, set to kasm-helm's version.

    kasm-helm is the anchor because set_versions.py already moves it on the Kasm
    Workspaces release line; this brings the rest of the repo to the same number
    in one pass, which is what keeps ``--check`` green after a release bump.
    """
    anchor = charts.get("kasm-helm")
    if anchor is None:
        raise ChartError("charts/kasm-helm not found; --align has nothing to align to")
    version = anchor.version
    if not SEMVER_RE.match(version):
        raise ChartError(
            f"charts/kasm-helm declares {version!r}, which is not a SemVer 2 version"
        )

    edits: list[Edit] = []
    # Own versions -- every chart except the ones another tool owns.  kasm-helm's
    # own version is set_versions.py's (and already the anchor); its pin below is
    # still ours to move.
    for chart in sorted(charts.values(), key=lambda c: c.name):
        if chart.name in EXTERNALLY_VERSIONED_CHARTS or chart.version == version:
            continue
        edits.append(
            Edit(chart.chart_yaml, chart.version_line,
                 chart.lines[chart.version_line - 1],
                 replace_scalar(chart.lines[chart.version_line - 1], version),
                 f"{chart.name}'s own version (aligned to kasm-helm)")
        )
    # Every file:// pin, charts/kasm-platform's pin on kasm-helm included.
    for parent in sorted(charts.values(), key=lambda c: c.name):
        for dep in parent.local_dependencies():
            if dep.version == version:
                continue
            edits.append(
                Edit(parent.chart_yaml, dep.version_line,
                     parent.lines[dep.version_line - 1],
                     replace_scalar(parent.lines[dep.version_line - 1], version),
                     f"{parent.name}'s pin on {dep.name}")
            )
    return version, edits


def align(write: bool) -> int:
    charts = load_charts()
    version, edits = plan_align(charts)

    if not edits:
        print(f"Nothing to do: every agent-family chart and pin already matches kasm-helm at {version}.")
        return 0

    verb = "Applying" if write else "Would apply"
    print(f"{verb} {len(edits)} edit(s) to align every agent-family chart to kasm-helm's {version}:")
    print("")
    for edit in edits:
        rel = edit.path.relative_to(REPO_ROOT)
        print(f"  {rel}:{edit.line_no}  ({edit.why})")
        print(f"    - {edit.before.strip()}")
        print(f"    + {edit.after.strip()}")
    print("")

    if not write:
        print("Dry run -- nothing written.  Re-run with --write to apply.")
        return 0

    for edit in edits:
        chart = next(c for c in charts.values() if c.chart_yaml == edit.path)
        chart.lines[edit.line_no - 1] = edit.after
    for path in dict.fromkeys(e.path for e in edits):
        next(c for c in charts.values() if c.chart_yaml == path).write()

    print(f"Wrote {len({e.path for e in edits})} Chart.yaml file(s).")
    print("")
    print("Next: refresh the lock files, which still name the old version --")
    print("  ./bin/helm dependency update charts/kasm-agent")
    print("  ./bin/helm dependency update charts/kasm-platform")
    print("(`make set-version CHART_VERSION=...` runs this whole sequence for you.)")
    return 0


# --------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify every file:// pin matches the referenced chart's declared version",
    )
    parser.add_argument(
        "--bump",
        nargs=2,
        metavar=("CHART", "VERSION"),
        help="set CHART's version to VERSION and update every pin that names it",
    )
    parser.add_argument(
        "--align",
        action="store_true",
        help="set every agent-family chart (and pin) to charts/kasm-helm's current version",
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="with --bump or --align, actually write the files (default: dry run)",
    )
    args = parser.parse_args()

    if sum(bool(m) for m in (args.check, args.bump, args.align)) > 1:
        parser.error("--check, --bump and --align are mutually exclusive")
    if args.write and not (args.bump or args.align):
        parser.error("--write only applies to --bump or --align")
    if not (args.check or args.bump or args.align):
        parser.error("one of --check, --bump or --align is required")

    try:
        if args.check:
            return check()
        if args.align:
            return align(args.write)
        return bump(args.bump[0], args.bump[1], args.write)
    except ChartError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
