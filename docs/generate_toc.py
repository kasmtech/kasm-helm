import os
import re
import argparse
from collections import defaultdict, OrderedDict

TOC_START = "<!-- BEGIN TOC -->"
TOC_END = "<!-- END TOC -->"

def extract_metadata(filepath):
    metadata = {}
    try:
        with open(filepath, encoding="utf-8") as f:
            lines = f.readlines()
        if lines and lines[0].strip() == "---":
            yaml_lines = []
            for line in lines[1:]:
                if line.strip() == "---":
                    break
                yaml_lines.append(line)
            for line in yaml_lines:
                match = re.match(r'^([\w\-]+):\s*(.*)$', line.strip())
                if match:
                    key, value = match.groups()
                    metadata[key.lower()] = value.strip()
    except Exception:
        pass
    return metadata

def extract_first_h1(filepath):
    try:
        with open(filepath, encoding="utf-8") as f:
            for line in f:
                if line.strip().startswith("# "):
                    return line.strip()[2:].strip()
    except Exception:
        pass
    return None

def get_display_title(filename):
    return filename.replace('.md', '').replace('-', ' ').replace('_', ' ').title()

def folder_breadcrumb(rel_dir):
    if rel_dir in ('.', '', None):
        return "Helm Docs"
    parts = [part.replace('_', ' ').replace('-', ' ').title() for part in rel_dir.replace("\\", "/").split('/')]
    return " > ".join(parts)

def collect_markdown_files(root_dir):
    folder_docs = defaultdict(list)
    for dirpath, _, files in os.walk(root_dir):
        rel_dir = os.path.relpath(dirpath, root_dir)
        for file in files:
            if file.lower().endswith('.md') and not file.lower().startswith('readme'):
                rel_path = os.path.join(rel_dir, file) if rel_dir != '.' else file
                rel_path = rel_path.replace("\\", "/")
                abs_path = os.path.join(dirpath, file)

                meta = extract_metadata(abs_path)
                title = meta.get('title') or get_display_title(file)
                description = meta.get('description') or extract_first_h1(abs_path) or "(No description)"
                section = folder_breadcrumb(rel_dir)

                folder_docs[section].append((title, rel_path, description))
    return folder_docs

def generate_toc(folder_docs):
    lines = []
    # Always show Helm Docs section first if it exists
    all_sections = sorted(folder_docs)
    if "Helm Docs" in folder_docs:
        all_sections.remove("Helm Docs")
        sections = ["Helm Docs"] + all_sections
    else:
        sections = all_sections

    for section in sections:
        files = sorted(folder_docs[section], key=lambda x: x[0].lower())
        lines.append(f"\n### {section}\n")
        lines.append("| Title | Description |")
        lines.append("|---|---|")
        for title, path, desc in files:
            lines.append(f"| [{title}]({path}) | {desc} |")
    return "\n".join(lines) + "\n"

def insert_toc_into_readme(readme_path, toc):
    with open(readme_path, encoding="utf-8") as f:
        content = f.read()

    start_idx = content.find(TOC_START)
    end_idx = content.find(TOC_END)

    if start_idx == -1 or end_idx == -1 or end_idx <= start_idx:
        print(f"ERROR: Markers {TOC_START} and/or {TOC_END} not found or invalid in {readme_path}")
        return

    before = content[:start_idx + len(TOC_START)]
    after = content[end_idx:]

    new_content = before + "\n\n" + toc + "\n" + after

    with open(readme_path, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"TOC inserted between markers in {readme_path}")

def main():
    parser = argparse.ArgumentParser(description="Insert generated TOC with breadcrumb sections into README.md between markers.")
    parser.add_argument("directory", nargs="?", default=".", help="Directory to scan for .md files (default: current directory)")
    parser.add_argument("--readme", default="README.md", help="README file to update (default: README.md)")
    args = parser.parse_args()

    folder_docs = collect_markdown_files(args.directory)
    toc = generate_toc(folder_docs)
    insert_toc_into_readme(args.readme, toc)

if __name__ == "__main__":
    main()
