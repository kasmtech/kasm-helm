# Publish the charts

> **Applies to:** both

## Why this is needed

Four of the ten charts in this repository are published as standalone releases to
`oci://registry-1.docker.io/kasmweb/`: `kasm-platform`, `kasm-agent`, `kasm-agent-crds` and
`kasm-egress-installer`. The other five agent-family charts (`kasm-agent-operator`,
`kasm-otel-collector`, `kasm-agent-instance`, `kasm-node-prep`, `kasm-video-device-plugin`) travel
inside `kasm-agent`'s archive and are never published on their own: a release nobody should install
alone is not offered. `kasm-helm` is published by its own job, on the control plane's release
cadence. A published archive embeds every dependency, so an install from it contacts no repository.

## Before you start

- A checkout on `develop` or a `release/*` branch. Only those branches build and publish; the
  push itself happens in GitLab, with the `DOCKER_HUB_USERNAME` and `DOCKER_HUB_PASSWORD` CI
  variables, never from a laptop.
- Network access. Three of `kasm-agent`'s nine dependencies are remote: `csi-driver-rclone` over
  OCI, `gpu-operator` and `nfs-server-provisioner` over HTTP repositories.
- `bin/helm` and `bin/yq`, from `make tools`.

## Steps

1. Bump the versions of the charts that changed. Every `file://` dependency pin is maintained by
   hand: `kasm-agent` pins its six local subcharts, and `kasm-platform` pins `kasm-helm` and
   `kasm-agent`. `scripts/agent_versions.py --bump` moves a chart's own version and every pin
   naming it together; it is a dry run until `--write`:

   ```console
   python3 scripts/agent_versions.py --bump kasm-agent-instance 0.2.0
   python3 scripts/agent_versions.py --bump kasm-agent-instance 0.2.0 --write
   helm dependency update charts/kasm-agent      # refresh Chart.lock of the parent that pins it
   ```

   `kasm-helm`'s own version belongs to `scripts/set_versions.py` (`make readme CHART_VERSION=...`).
   After a control plane bump, run `--bump kasm-helm <version> --write` to catch `kasm-platform`'s
   pin up, then `helm dependency update charts/kasm-platform`. `kasm-agent-crds` and
   `kasm-agent-operator` carry one version, because they ship one set of CRDs.

2. Check the pins. A stale pin is only half-loud: `helm dependency build` refuses it, but
   `helm package` against an already-staged `charts/` directory exits 0 and embeds the old archive.

   ```console
   make version-check-agent
   ```

3. Stage the dependencies, inside-out. `helm package` does not resolve dependencies; it archives
   whatever `charts/` already holds. `make deps-agent` builds `charts/kasm-agent` first and only
   then `charts/kasm-platform`, which archives `kasm-agent` off disk. Reversed, the embedded
   `kasm-agent` is missing all nine of its own dependencies and the composed release installs a
   hollow agent half.

   ```console
   make deps-agent
   ```

4. Package, and write the airgap image list:

   ```console
   make package-agent          # dist/kasm-agent-<version>.tgz
   make package-agent-all      # plus kasm-platform, kasm-agent-crds and kasm-egress-installer
   make images-agent           # dist/kasm-agent-images.txt
   make images-check           # the independent yq extractor agrees with that list
   ```

   The `helm-build-agent` GitLab job runs `make version-check-agent` and then
   `make deps-agent package-agent package-agent-all images-agent`, in that order, and keeps
   `dist/*.tgz` and `dist/kasm-agent-images.txt` as artifacts. `make images-check` runs in the
   `docs-check` job (`images` matrix entry).

5. Push. `helm-deploy-agent-docker-hub` is a **manual** job on `develop` and `release/*`: the agent
   charts sit at one preview version, so an automatic push would re-push the same version on every
   commit. The job logs in to Docker Hub and, for each archive in `dist/`, probes the registry for
   that chart and version. A version that is not there is pushed; one that is already there is
   refused, unless the pipeline sets `FORCE_REPUBLISH=true` (Run pipeline → Variables, or the manual
   job's own variables), which makes replacing a published preview a deliberate act.

6. **Rancher's own catalog, optional.** Any Rancher installation can add `https://helm.kasm.com`
   or the OCI URLs as a repository and install the published charts as they are
   ([Install from the Rancher catalog](install/rancher.md)); nothing here is needed for that.
   Appearing in the **Partners** catalog that every Rancher ships with is a submission to SUSE's
   `rancher/partner-charts` repository on GitHub: a `packages/kasm/<chart>/package.yaml` per chart
   that names the upstream chart's HTTP repository URL and a fixed version, regenerated with their
   `make prepare` / `make patch` / `make charts` workflow and reviewed by SUSE. Two things follow:

   - the chart must be in a public **HTTP-indexed** repository, so the agent-family charts need the
     `helm-deploy-gitlab` treatment `kasm-helm` already gets (the index at `https://helm.kasm.com`),
     not only the OCI push;
   - the version must be a release, not a prerelease: Rancher hides prereleases by default, and
     the partner repository pins versions that never change.

   The `catalog.cattle.io/*` annotations, `app-readme.md` and `questions.yaml` the submission needs
   are already in each published chart; `make rancher-check` verifies them and fails on a question
   whose `variable` names no value.

## Verify

The job log shows one line per archive:

```
PUBLISH    kasm-agent 1.1200.0-develop -- not yet in kasmweb/
PUBLISH    kasm-platform 1.1200.0-develop -- not yet in kasmweb/
PUBLISH    kasm-agent-crds 1.1200.0-develop -- not yet in kasmweb/
PUBLISH    kasm-egress-installer 1.1200.0-develop -- not yet in kasmweb/
```

A `REFUSED` line fails the job and prints the bump-or-force instructions; `REPUBLISH` means
`FORCE_REPUBLISH=true` overwrote a published version.

Confirm the published version from anywhere:

```console
helm show chart oci://registry-1.docker.io/kasmweb/kasm-agent --version <version> | head -3
```

```
apiVersion: v2
appVersion: develop
dependencies:
```

Confirm the archive is self-contained (nine embedded dependencies):

```console
helm pull oci://registry-1.docker.io/kasmweb/kasm-agent --version <version>
tar tzf kasm-agent-<version>.tgz | grep -c '^kasm-agent/charts/[^/]*/Chart.yaml$'
```

```
9
```

## Chart values

None. Publishing sets no chart values. The versions live in each chart's `Chart.yaml`, and the
`file://` pins in `charts/kasm-agent/Chart.yaml` and `charts/kasm-platform/Chart.yaml`.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `REFUSED <chart> <version> -- already in kasmweb/` | That version is published and `FORCE_REPUBLISH` is not `true`. | Bump the chart (`--bump ... --write`, then `make version-check-agent`), or re-run the job with `FORCE_REPUBLISH=true`. |
| `make version-check-agent` fails | A `file://` pin fell behind the chart it names; `kasm-helm` after `make readme CHART_VERSION=...` is the usual one. | `python3 scripts/agent_versions.py --bump <chart> <version> --write` |
| `can't get a valid version for dependency` from `helm dependency build` | The same stale pin. | The same fix. |
| `ERROR: no dist/*.tgz artifacts to publish` | `helm-build-agent` did not run in this pipeline, or its artifacts expired. | Re-run the build job in the same pipeline, then the deploy job. |
| The published `kasm-platform` installs an agent with no subcharts | `charts/kasm-platform` was packaged before `charts/kasm-agent` was staged. | `make deps-agent package-agent-all`; never `helm package` by hand. |
| `make images-check` reports `MISSING` | A template references an image under a key shape the `images-agent` extractor does not see. | Fix the extractor in the Makefile, not the list; the list is generated. |
| `make rancher-check` reports `does not resolve to a key` | A `questions.yaml` variable path has a typo, or names a value the chart (or the dependency its prefix names) does not declare. | Fix the path; the form otherwise writes a value nothing reads. |

## Decisions

- [ ] Every chart that changed has a new version, and `make version-check-agent` passes.
- [ ] `make deps-agent` ran on this checkout before packaging.
- [ ] `make images-check` passes, so the airgap list matches the archives.
- [ ] `make rancher-check` passes, so the Rancher catalog files match the values.
- [ ] The pipeline is on `develop` or `release/*`, and the log shows `PUBLISH` for every archive.
- [ ] `FORCE_REPUBLISH=true` was used only to replace a preview on purpose.
