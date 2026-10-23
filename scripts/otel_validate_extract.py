#!/usr/bin/env python3
"""Extract OTel Collector configs (and their pinned image) from a rendered chart manifest.

Used by `make otel-validate` to pull the `config.yaml` payload out of every otel-* ConfigMap
in a rendered manifest, write each to its own file, and pair it with the collector image the
chart actually deploys it under (read from the rendered Deployment/StatefulSet, not
hardcoded), so the docker `validate` check stays in lockstep with values.yaml image bumps.

Usage: otel_validate_extract.py <rendered.yaml> <outdir> <manifest.txt>
Writes "<cfg_path>|<image>" lines to <manifest.txt>, one per otel ConfigMap found.
"""
import os
import sys

import yaml


def component(doc):
    return doc.get("metadata", {}).get("labels", {}).get("app.kubernetes.io/component", "")


def main(rendered, outdir, manifest):
    docs = [d for d in yaml.safe_load_all(open(rendered)) if d]

    # The otel-gateway ConfigMap pairs 1:1 with its own Deployment (same
    # component label). The db and nginx sidecar ConfigMaps don't - their host workload's
    # component is "db"/"connection-proxy"/"proxy" - so any "otel-sidecar" container's image
    # is used for those instead; all sidecars share components.otelSidecar.image.
    workload_images = {}
    sidecar_image = None
    for d in docs:
        if d.get("kind") not in ("Deployment", "StatefulSet"):
            continue
        for c in d["spec"]["template"]["spec"].get("containers", []):
            if c["name"] == "otel-sidecar":
                sidecar_image = c["image"]
            elif component(d).startswith("otel-"):
                workload_images[component(d)] = c["image"]

    count = 0
    with open(manifest, "w") as m:
        for d in docs:
            if d.get("kind") != "ConfigMap" or "config.yaml" not in d.get("data", {}):
                continue
            comp = component(d)
            if not comp.startswith("otel-"):
                continue
            image = workload_images.get(comp, sidecar_image)
            if not image:
                sys.exit(f"otel_validate_extract: no collector image found for component {comp}")
            name = d["metadata"]["name"]
            cfg_path = os.path.join(outdir, name + ".yaml")
            with open(cfg_path, "w") as f:
                f.write(d["data"]["config.yaml"])
            m.write(f"{cfg_path}|{image}\n")
            count += 1

    if count == 0:
        sys.exit("otel_validate_extract: no otel ConfigMaps found in rendered manifest")


if __name__ == "__main__":
    main(*sys.argv[1:4])
