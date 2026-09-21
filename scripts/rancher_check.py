#!/usr/bin/env python3
"""
Verify the Rancher catalog packaging of the published charts.

Rancher's Apps catalog reads three things a plain Helm client ignores: the `catalog.cattle.io/*`
annotations in Chart.yaml, `app-readme.md` (the text on the chart tile), and `questions.yaml` (the
install form). None of them is exercised by `helm lint`, `helm template` or helm-unittest, and a
typo in a question's `variable` path only shows up as a form field that silently writes a value
nothing reads. This script is the guard:

  * every published chart carries the annotation set Rancher needs, and its
    `catalog.cattle.io/kube-version` agrees with the chart's own `kubeVersion`;
  * the two umbrella charts name the CRD chart in `catalog.cattle.io/auto-install`, at the same
    version, and the CRD chart is hidden and declares what it provides;
  * `app-readme.md` exists and is not empty;
  * every `questions.yaml` parses, every `variable` (subquestions included) resolves to a key in the
    chart's effective values -- its own values.yaml, then the values.yaml of the `file://` dependency
    an aliased prefix names -- every enum `default` is one of its `options`, and every `show_if`
    refers to variables the form defines.

Usage:
    python3 scripts/rancher_check.py          # == make rancher-check
    python3 scripts/rancher_check.py -v       # list every resolved variable

Exit status is non-zero on the first chart with findings; every finding is printed.
YAML is read through bin/yq (`make tools`), so the script needs no third-party Python modules.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
YQ = ROOT / "bin" / "yq"

# The charts published as standalone releases (Makefile: AGENT_PUBLISH_CHART_DIRS plus kasm-helm).
# `form` says whether Rancher renders an install form for it: the CRD chart is hidden and installed
# on the umbrellas' behalf, so it has no questions.yaml.
PUBLISHED = {
    "kasm-platform": {"form": True, "umbrella": True},
    "kasm-agent": {"form": True, "umbrella": True},
    "kasm-agent-crds": {"form": False, "umbrella": False},
    "kasm-egress-installer": {"form": True, "umbrella": False},
    "kasm-helm": {"form": True, "umbrella": False},
}
CRD_CHART = "kasm-agent-crds"

REQUIRED_ANNOTATIONS = (
    "catalog.cattle.io/display-name",
    "catalog.cattle.io/release-name",
    "catalog.cattle.io/kube-version",
    "catalog.cattle.io/rancher-version",
    "catalog.cattle.io/permits-os",
)
QUESTION_TYPES = {
    "string", "multiline", "boolean", "int", "enum", "password", "storageclass", "hostname",
    "pvc", "secret",
}
SHOW_IF_RE = re.compile(r"([A-Za-z0-9_.\-]+)\s*(?:=|!=)\s*[^&|]*")


def load_yaml(path: Path):
    """Parse a YAML file into Python objects via yq, so PyYAML is not a requirement."""
    if not YQ.exists():
        sys.exit(f"{YQ} is missing: run `make tools` first")
    out = subprocess.run([str(YQ), "-o=json", "."], input=path.read_text(), capture_output=True, text=True)
    if out.returncode != 0:
        raise ValueError(f"{path}: {out.stderr.strip()}")
    return json.loads(out.stdout) if out.stdout.strip() else None


class Chart:
    def __init__(self, path: Path):
        self.path = path
        self.name = path.name
        self.meta = load_yaml(path / "Chart.yaml") or {}
        self.values = load_yaml(path / "values.yaml") or {}
        # alias (or name) -> chart directory, for the file:// dependencies only. Remote dependencies
        # have no values.yaml on disk; the keys the umbrella itself sets for them (`enabled`) live in
        # its own values.yaml and resolve there.
        self.local_deps: dict[str, Path] = {}
        for dep in self.meta.get("dependencies") or []:
            repo = dep.get("repository", "")
            if repo.startswith("file://"):
                self.local_deps[dep.get("alias") or dep["name"]] = (path / repo[len("file://"):]).resolve()

    def annotation(self, key: str):
        return (self.meta.get("annotations") or {}).get(key)

    def resolve(self, dotted: str) -> bool:
        """True when a dotted values path exists in this chart's values or in the values of the
        local dependency its first segment names (recursively). A `global.*` path resolves when the
        chart declares `global`, as every published chart does."""
        parts = dotted.split(".")
        node = self.values
        for part in parts:
            if isinstance(node, dict) and part in node:
                node = node[part]
                continue
            # Not in this chart's values. An umbrella restates only a few of a dependency's keys
            # (`kasm-agent.agent.inClusterControlPlane` but not `kasm-agent.agent.manager`), so the
            # rest of the path is looked up in the dependency's own values.
            if parts[0] in self.local_deps:
                return Chart(self.local_deps[parts[0]]).resolve(".".join(parts[1:]))
            return False
        return True


def check_chart(chart: Chart, spec: dict, verbose: bool) -> list[str]:
    findings: list[str] = []
    ann = chart.meta.get("annotations") or {}
    for key in REQUIRED_ANNOTATIONS:
        if not ann.get(key):
            findings.append(f"Chart.yaml: annotation {key} is missing")
    if not chart.meta.get("kubeVersion"):
        findings.append("Chart.yaml: kubeVersion is missing")
    elif ann.get("catalog.cattle.io/kube-version") and ann["catalog.cattle.io/kube-version"] != chart.meta["kubeVersion"]:
        findings.append(
            f"Chart.yaml: catalog.cattle.io/kube-version ({ann['catalog.cattle.io/kube-version']}) "
            f"differs from kubeVersion ({chart.meta['kubeVersion']})"
        )
    if spec["umbrella"]:
        want = f"{CRD_CHART}=match"
        if ann.get("catalog.cattle.io/auto-install") != want:
            findings.append(f"Chart.yaml: catalog.cattle.io/auto-install must be {want!r}, is {ann.get('catalog.cattle.io/auto-install')!r}")
        crd_version = (load_yaml(ROOT / "charts" / CRD_CHART / "Chart.yaml") or {}).get("version")
        if crd_version != chart.meta.get("version"):
            findings.append(
                f"Chart.yaml: version {chart.meta.get('version')} differs from {CRD_CHART}'s {crd_version}; "
                f"auto-install `=match` needs them equal"
            )
    if chart.name == CRD_CHART:
        if str(ann.get("catalog.cattle.io/hidden")).lower() != "true":
            findings.append("Chart.yaml: catalog.cattle.io/hidden must be \"true\" on the CRD chart")
        if not ann.get("catalog.cattle.io/provides-gvr"):
            findings.append("Chart.yaml: catalog.cattle.io/provides-gvr is missing on the CRD chart")

    readme = chart.path / "app-readme.md"
    if not readme.exists() or not readme.read_text().strip():
        findings.append("app-readme.md is missing or empty")

    questions = chart.path / "questions.yaml"
    if not spec["form"]:
        if questions.exists():
            findings.append("questions.yaml exists on a hidden chart; Rancher never shows its form")
        return findings
    if not questions.exists():
        findings.append("questions.yaml is missing")
        return findings
    try:
        doc = load_yaml(questions)
    except ValueError as exc:
        findings.append(f"questions.yaml does not parse: {exc}")
        return findings
    items = (doc or {}).get("questions")
    if not isinstance(items, list) or not items:
        findings.append("questions.yaml: `questions` must be a non-empty list")
        return findings

    variables: set[str] = set()
    flat: list[tuple[dict, str]] = []
    for q in items:
        flat.append((q, "question"))
        for sub in q.get("subquestions") or []:
            flat.append((sub, f"subquestion of {q.get('variable')}"))
    for q, where in flat:
        var = q.get("variable")
        if not var:
            findings.append(f"questions.yaml: a {where} has no `variable`")
            continue
        if var in variables:
            findings.append(f"questions.yaml: {var} is defined twice")
        variables.add(var)
        if not q.get("label"):
            findings.append(f"questions.yaml: {var} has no `label`")
        qtype = q.get("type")
        if qtype not in QUESTION_TYPES:
            findings.append(f"questions.yaml: {var} has type {qtype!r}; Rancher's form types are {sorted(QUESTION_TYPES)}")
        if qtype == "enum":
            options = q.get("options") or []
            if not options:
                findings.append(f"questions.yaml: enum {var} has no `options`")
            elif "default" in q and q["default"] not in options:
                findings.append(f"questions.yaml: enum {var} default {q['default']!r} is not one of {options}")
        if not chart.resolve(var):
            findings.append(f"questions.yaml: {var} does not resolve to a key in the chart's values")
        elif verbose:
            print(f"  ok  {var}")
    for q, _ in flat:
        for cond in (q.get("show_if"), q.get("show_subquestion_if")):
            if not isinstance(cond, str) or "=" not in cond:
                continue
            for ref in SHOW_IF_RE.findall(cond):
                if ref not in variables:
                    findings.append(f"questions.yaml: {q.get('variable')} show_if refers to {ref}, which no question defines")
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-v", "--verbose", action="store_true", help="list every resolved question variable")
    args = parser.parse_args()

    failed = False
    for name, spec in PUBLISHED.items():
        chart_dir = ROOT / "charts" / name
        if not chart_dir.exists():
            print(f"{name}: charts/{name} does not exist")
            failed = True
            continue
        if args.verbose:
            print(f"{name}:")
        findings = check_chart(Chart(chart_dir), spec, args.verbose)
        if findings:
            failed = True
            print(f"{name}: {len(findings)} finding(s)")
            for f in findings:
                print(f"  - {f}")
        else:
            print(f"{name}: OK")
    if failed:
        print("\nrancher-check: FAILED")
        return 1
    print("\nrancher-check: every published chart carries its Rancher catalog packaging.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
