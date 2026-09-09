#!/usr/bin/env python3
"""Relative-link checker for the repo's markdown. Reports links whose target file
(and #anchor, when given) does not exist."""
import re, sys, pathlib, urllib.parse

ROOT = pathlib.Path(".").resolve()
FILES = [p for p in ROOT.rglob("*.md")
         if not any(part in (".git", ".rendered", ".rendered-infra", "node_modules", ".helm", "bin", "dist")
                    for part in p.relative_to(ROOT).parts)]
LINK = re.compile(r'\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)')

def anchors(path):
    out = set()
    try:
        text = path.read_text()
    except Exception:
        return out
    fence = False
    for line in text.splitlines():
        if re.match(r'^\s*(```|~~~)', line):
            fence = not fence
            continue
        if fence:
            continue                      # '#' inside a code fence is a comment, not a heading
        m = re.match(r'#{1,6}\s+(.*)', line)
        if m:
            slug = m.group(1).strip().lower()
            slug = re.sub(r'`|\*|_|\[|\]|\(|\)|<[^>]*>', '', slug)
            slug = re.sub(r'[^\w\s-]', '', slug)
            # GitHub replaces each space individually; it does not collapse runs
            out.add(slug.replace(' ', '-'))
        for a in re.findall(r'<a\s+(?:id|name)="([^"]+)"', line):
            out.add(a)
        for a in re.findall(r'\bid="([^"]+)"', line):
            out.add(a)
    return out

bad = []
for f in sorted(FILES):
    text = f.read_text()
    for raw in LINK.findall(text):
        if raw.startswith(("http://", "https://", "mailto:", "tel:")):
            continue
        target, _, frag = raw.partition("#")
        target = urllib.parse.unquote(target)
        if not target:
            if frag and frag not in anchors(f):
                bad.append((f.relative_to(ROOT), raw, "missing anchor in same file"))
            continue
        dest = (f.parent / target).resolve()
        if not dest.exists():
            bad.append((f.relative_to(ROOT), raw, "no such file"))
        elif frag and dest.suffix == ".md" and frag not in anchors(dest):
            bad.append((f.relative_to(ROOT), raw, "missing anchor"))

fragile = []
for f in sorted(FILES):
    for raw in LINK.findall(f.read_text()):
        if raw.startswith(("http://", "https://", "mailto:", "tel:")):
            continue
        frag = raw.partition("#")[2]
        if "--" in frag:
            fragile.append((f.relative_to(ROOT), raw))

for src, link, why in bad:
    print(f"{src}: {link}  [{why}]")
for src, link in fragile:
    print(f"{src}: {link}  [fragile anchor: '--' comes from a character deleted between two "
          f"spaces (& - /), and renderers disagree about it. Reword the heading.]")
print(f"\n{len(bad)} broken link(s), {len(fragile)} fragile anchor(s) across {len(FILES)} markdown files")
sys.exit(1 if bad or fragile else 0)
