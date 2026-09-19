"""Regression test for kasm-helm-6ph: _merge_into_existing must not glue new
entries onto the previous line, and must be stable across repeated merges.

Run: python3 -m pytest tests/test_changelog_merge.py
"""
import importlib.util
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "changelog-draft.py"
spec = importlib.util.spec_from_file_location("changelog_draft", SCRIPT)
changelog_draft = importlib.util.module_from_spec(spec)
sys.modules["changelog_draft"] = changelog_draft
spec.loader.exec_module(changelog_draft)

_merge_into_existing = changelog_draft._merge_into_existing


def _entry_lines(section: str) -> list:
    return [l for l in section.splitlines() if l.startswith("- ") or l.startswith("-<")]


EXISTING = (
    "## [Unreleased]\n"
    "\n### Added\n\n"
    "- initial add <!-- hash:aaa -->\n"
    "\n### Fixed\n\n"
    "- initial fix <!-- hash:bbb -->\n"
)
FOLLOWED_BY_RELEASE = EXISTING + "\n## [1.0.0]\n\nFirst release.\n"


def test_insert_into_last_category_does_not_glue():
    """Inserting into 'Fixed' (the last category) must not concatenate onto
    the previous entry's line."""
    merged = _merge_into_existing(EXISTING, {"Fixed": ["new fix <!-- hash:ccc -->"]})
    for line in _entry_lines(merged):
        assert line.startswith("- "), f"glued/malformed entry line: {line!r}"
    assert "initial fix <!-- hash:bbb -->\n- new fix" in merged


def test_blank_line_before_next_release_heading_preserved():
    """The blank line separating [Unreleased] from the next '## [x.y.z]'
    heading must survive a merge, not just the first run."""
    section_only = changelog_draft._UNRELEASED_RE.search(FOLLOWED_BY_RELEASE).group(0)
    merged = _merge_into_existing(section_only, {"Fixed": ["new fix <!-- hash:ccc -->"]})
    rebuilt = FOLLOWED_BY_RELEASE.replace(section_only, merged)
    assert "\n\n## [1.0.0]" in rebuilt


def test_merge_idempotent_across_reruns():
    """Feeding progressively more buckets through the merge three times in a
    row must never regress: every entry line stays well-formed."""
    text = EXISTING
    runs = [
        {"Fixed": ["fix 0 <!-- hash:0f -->"]},
        {"Added": ["add 1 <!-- hash:1a -->"]},
        {"Fixed": ["fix 2 <!-- hash:2f -->"]},
    ]
    for i, buckets in enumerate(runs):
        text = _merge_into_existing(text, buckets)
        for line in _entry_lines(text):
            assert line.startswith("- "), f"run {i}: glued/malformed entry line: {line!r}"

    # A no-op merge (no new buckets) must be byte-stable.
    stable = _merge_into_existing(text, {})
    assert stable == text


if __name__ == "__main__":
    import pytest
    sys.exit(pytest.main([__file__, "-v"]))
