#!/usr/bin/env python3
"""Print a space-separated list of images required by the kind cluster,
sourced directly from the chart values.yaml so the Makefile stays in sync.

Intentionally avoids third-party dependencies (no pyyaml) because this
script is called at Makefile parse time via $(shell ...) before any
install targets have run.
"""

import sys

values_path = sys.argv[1] if len(sys.argv) > 1 else "charts/kasm-helm/values.yaml"

with open(values_path) as f:
    lines = f.readlines()


def indent(line: str) -> int:
    return len(line) - len(line.lstrip())


def find_key_value(key: str, search_lines: list) -> str:
    """Return the value for the first 'key: value' line found."""
    for line in search_lines:
        stripped = line.strip()
        if stripped.startswith(f"{key}:"):
            return stripped[len(key) + 1:].strip()
    raise ValueError(f"Key '{key}' not found")


def get_block(start_key: str, parent_lines: list) -> list:
    """Return the lines belonging to the first occurrence of 'start_key:'
    in parent_lines, based on indentation."""
    for i, line in enumerate(parent_lines):
        stripped = line.strip()
        if stripped.startswith(f"{start_key}:") or stripped == f"{start_key}:":
            key_indent = indent(line)
            block = []
            for child in parent_lines[i + 1:]:
                if child.strip() == "":
                    continue
                if indent(child) > key_indent:
                    block.append(child)
                else:
                    break
            return block
    raise ValueError(f"Key '{start_key}' not found in block")


def get_image(block: list) -> str:
    image_block = get_block("image", block)
    repo = find_key_value("repository", image_block)
    tag = find_key_value("tag", image_block)
    return f"{repo}:{tag}"


# Top-level sections
components_block = get_block("components", lines)
database_block = get_block("database", lines)

images = [
    get_image(get_block("api", components_block)),
    get_image(get_block("manager", components_block)),
    get_image(get_block("proxy", components_block)),
    get_image(database_block),
    get_image(get_block("guac", components_block)),
    get_image(get_block("rdpGateway", components_block)),
    get_image(get_block("rdpHttpsGateway", components_block)),
    "postgres:16",
    "nginx:1.30-alpine",
]

print(" ".join(images))
