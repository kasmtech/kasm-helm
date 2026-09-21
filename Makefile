SHELL := /usr/bin/env bash

CHART_DIR := charts/kasm-helm
TEST_VALUES_DIR := tests/values

# The kasm-agent umbrella chart (charts/kasm-agent) and its 5 local subcharts. Wired into the
# *-agent targets below (deps-agent/lint-agent/unittest-agent/render-agent), which are folded into
# the existing lint/unittest/render aggregates so `make test` covers both chart families.
# charts/kasm-agent also has 3 remote (non-Kasm) dependencies declared in its Chart.yaml
# (csi-driver-rclone, gpu-operator, nfs-server-provisioner); those are fetched by `deps-agent` but
# have no chart directory of their own here.
AGENT_CHART_DIR := charts/kasm-agent
AGENT_LOCAL_CHART_DIRS := \
  charts/kasm-agent-operator \
  charts/kasm-otel-collector \
  charts/kasm-agent-instance \
  charts/kasm-node-prep \
  charts/kasm-video-device-plugin \
  charts/kasm-egress-installer
AGENT_ALL_CHART_DIRS := $(AGENT_LOCAL_CHART_DIRS) $(AGENT_CHART_DIR)
AGENT_TEST_VALUES_DIR := tests/values-agent

# The CRD-only chart (charts/kasm-agent-crds). Deliberately NOT a member of
# $(AGENT_LOCAL_CHART_DIRS): it is not a subchart of $(AGENT_CHART_DIR) and nothing depends on it.
# It is a standalone release that ships the same five CustomResourceDefinitions
# charts/kasm-agent-operator/crds/ holds, as ordinary templates, so a fleet can upgrade CRD schemas
# with `helm upgrade` instead of the kubectl side channel. It rides along on lint-agent,
# unittest-agent, and render-agent, and `crds-sync-check` guards the two copies against drift.
AGENT_CRDS_CHART_DIR := charts/kasm-agent-crds
AGENT_CRDS_SOURCE_DIR := charts/kasm-agent-operator/crds

# The kasm-platform umbrella chart (charts/kasm-platform) composes $(CHART_DIR) and
# $(AGENT_CHART_DIR) into one release. It has no subcharts of its own beyond those two file://
# dependencies, so it rides along on the *-agent targets rather than getting its own family.
#
# Dependency build order matters: `helm dependency build charts/kasm-platform` packages
# charts/kasm-agent as it finds it on disk, charts/ directory included, so kasm-agent's own 9
# dependencies must already be staged or the resulting archive is missing them. deps-agent builds
# them in that order.
PLATFORM_CHART_DIR := charts/kasm-platform

# The agent-family charts published as standalone releases to
# oci://registry-1.docker.io/kasmweb/ -- what `package-agent-all` writes into dist/ and what the
# GitLab `helm-deploy-agent-docker-hub` job pushes. Deliberately a subset of $(ALL_CHART_DIRS):
# the five charts that are only ever consumed as subcharts of $(AGENT_CHART_DIR) travel inside its
# archive and have no standalone install story, so publishing them separately would offer a
# release nobody should install.
#
# charts/kasm-egress-installer is the exception and appears here as well as in
# $(AGENT_LOCAL_CHART_DIRS): the CNI shim is useful on a cluster that runs no other Kasm component
# (its DaemonSet is what a platform team reviews and rolls out on its own schedule), so it is
# published both embedded in kasm-agent and on its own.
AGENT_PUBLISH_CHART_DIRS := \
  $(AGENT_CHART_DIR) \
  $(PLATFORM_CHART_DIR) \
  $(AGENT_CRDS_CHART_DIR) \
  charts/kasm-egress-installer

# Every chart in the repo, kasm-helm plus all 9 kasm-agent-family charts. Used by the *-all doc
# targets (readme-all/readme-check-all/changelog-check-all) so adding a chart's docs coverage is a
# one-line change here instead of one per target.
ALL_CHART_DIRS := $(CHART_DIR) $(AGENT_ALL_CHART_DIRS) $(AGENT_CRDS_CHART_DIR) $(PLATFORM_CHART_DIR)

BIN_DIR := $(CURDIR)/bin
HELM := $(BIN_DIR)/helm
KUBECONFORM := $(BIN_DIR)/kubeconform
KYVERNO := $(BIN_DIR)/kyverno
KIND := $(BIN_DIR)/kind
KUBECTL := $(BIN_DIR)/kubectl
CLOUD_PROVIDER_KIND := $(BIN_DIR)/cloud-provider-kind
CRANE := $(BIN_DIR)/crane
HELM_DOCS := $(BIN_DIR)/helm-docs
# The HTML values-table renderers every chart's README.md.gotmpl used to carry as byte-identical
# copies now live once in _templates.gotmpl at the repo root, prepended to each chart's own
# README.md.gotmpl. helm-docs resolves a --template-files path that starts with ./ or ../ against
# --chart-search-root (a bare name is looked up inside each chart directory), so the same file is
# reached two ways: ../_templates.gotmpl from the repo root with --chart-search-root charts
# (readme-all, readme-check-all), and ../../_templates.gotmpl from inside $(CHART_DIR) (readme,
# readme-check), where the search root defaults to the chart itself.
HELM_DOCS_SHARED_TEMPLATE := _templates.gotmpl
HELM_DOCS_TEMPLATES_FROM_ROOT := --template-files=../$(HELM_DOCS_SHARED_TEMPLATE) --template-files=README.md.gotmpl
HELM_DOCS_TEMPLATES_FROM_CHART := --template-files=../../$(HELM_DOCS_SHARED_TEMPLATE) --template-files=README.md.gotmpl
YQ := $(BIN_DIR)/yq
HELM_PLUGINS_DIR := $(CURDIR)/.helm/plugins
PYTEST_IMAGE ?= kasm-e2e-pytest:latest
ifeq ($(strip $(PYTEST_IMAGE)),)
  PYTEST_IMAGE := kasm-e2e-pytest:latest
endif
KIND_KUBECONFIG ?= $(CURDIR)/.kind/kubeconfig
KIND_INTERNAL_KUBECONFIG ?= $(CI)

kind-fix-kubeconfig:
	@set -euo pipefail; \
	if [ "$${CI:-}" = "true" ] || echo "$${DOCKER_HOST:-}" | grep -q 'tcp://docker'; then \
	  docker_ip=$$(getent hosts docker | awk '{print $$1}' | head -n1); \
	  if [ -n "$$docker_ip" ]; then \
	    echo "$$docker_ip kind.kasm.local" >> /etc/hosts; \
	    sed -E -i 's#https://[^:]+:([0-9]+)#https://kind.kasm.local:\1#g' $(KIND_KUBECONFIG); \
	  fi; \
	fi
# Pinned versions for reproducibility
# Pinned to match the documented minimum in README.md ("Helm 3.18.x+").
# Bump in lockstep with the README requirement so host-side tooling
# (lint/render/kubeconform/unittest) matches what customers run.
HELM_VERSION := v3.18.6
KUBECONFORM_VERSION := v0.7.0
KYVERNO_VERSION := v1.16.2
HELM_UNITTEST_VERSION := v1.0.3
KIND_VERSION := v0.23.0
KUBECTL_VERSION := v1.30.7
CLOUD_PROVIDER_KIND_VERSION := v0.9.0
CRANE_VERSION := v0.20.6
# helm-docs regenerates charts/kasm-helm/README.md from values.yaml + README.md.gotmpl.
# Pinned so `make readme` and the readme-check guard in `make test` stay reproducible.
HELM_DOCS_VERSION := v1.14.2
# yq normalises the two copies of each CRD before `crds-sync-check` diffs them. Pinned for the same
# reason as the rest: the check runs in `make test`, and a formatting change between yq releases
# would otherwise turn into a spurious drift failure.
YQ_VERSION := v4.53.6
# The Kernel Module Management operator (https://kmm.sigs.k8s.io/), a *cluster* prerequisite rather
# than a build tool: charts/kasm-node-prep renders a kmm.sigs.x-k8s.io/v1beta1 Module custom
# resource when nodePrep.modules.v4l2loopback.method=kmm, and nothing applies that CRD but KMM
# itself. Upstream ships no Helm chart, so the install is a kustomize apply -- see the kmm-install
# target under "Cluster Prerequisites". Pinned because the Module schema this chart is written
# against is the one config/crd/bases/ carries at this tag.
KMM_VERSION := v2.7.0
KMM_KUSTOMIZE_URL := https://github.com/kubernetes-sigs/kernel-module-management/config/default?ref=$(KMM_VERSION)
# Optional registry mirror for an airgapped KMM install. Empty (the default) leaves the operator on its
# upstream gcr.io images -- the online path. Set it to the host[:port][/path] of your internal registry
# and use `kmm-install-mirrored` instead of `kmm-install`: every KMM image is then repointed at the
# mirror, keeping the upstream path suffix, e.g. gcr.io/k8s-staging-kmm/kernel-module-management-worker
# becomes $(KMM_IMAGE_REGISTRY)/k8s-staging-kmm/kernel-module-management-worker. Mirror the exact set
# `make images-agent` lists under "KMM mode" first. See the KMM offline runbook in
# charts/kasm-node-prep/README.md.
KMM_IMAGE_REGISTRY ?=
# The upstream image paths (registry stripped) the mirror substitution and images-agent both build on.
# Pinned to $(KMM_IMAGE_TAG) here; kaniko is versioned independently (see KMM_KANIKO_IMAGE).
#
# KMM publishes its images to a *staging* registry that tags release builds v<build date>-<version>;
# there is no bare v2.7.0 tag, and :latest (which the kustomize overlay references) is a rolling CI
# build. Verified 2026-09-14: the operator, webhook-server, worker and signimage images all exist at
# this tag (linux/amd64), while :latest webhook-server failed on an x86_64 node with "exec format
# error" and a bare :v2.7.0 was NotFound. Bump this together with KMM_VERSION.
KMM_IMAGE_TAG := v20260812-v2.7.0
KMM_UPSTREAM_REGISTRY := gcr.io
KMM_OPERATOR_PATH := k8s-staging-kmm/kernel-module-management-operator
KMM_WEBHOOK_PATH := k8s-staging-kmm/kernel-module-management-webhook-server
KMM_WORKER_PATH := k8s-staging-kmm/kernel-module-management-worker
KMM_SIGN_PATH := k8s-staging-kmm/kernel-module-management-signimage
# kaniko is a separate upstream project on its own release cadence; this pin is at your discretion.
# v1.23.2 is the current stable at the time of writing. Only needed in KMM build mode
# (modules.v4l2loopback.kmm.build.enabled=true), where the operator hands it to the in-cluster build.
KMM_KANIKO_PATH := kaniko-project/executor
KMM_KANIKO_VERSION := v1.23.2
# The registry every KMM image is pulled from after this Makefile resolves the mirror: KMM_IMAGE_REGISTRY
# when set, otherwise the upstream gcr.io. The five fully-resolved refs the kmm-install-mirrored target
# applies (`kubectl set image` for operator+webhook, `kubectl set env` for the operator's RELATED_IMAGE_*
# variables). The mirror keeps the upstream path suffix, so only the leading registry changes.
KMM_IMAGE_PREFIX := $(if $(strip $(KMM_IMAGE_REGISTRY)),$(strip $(KMM_IMAGE_REGISTRY)),$(KMM_UPSTREAM_REGISTRY))
KMM_OPERATOR_IMAGE := $(KMM_IMAGE_PREFIX)/$(KMM_OPERATOR_PATH):$(KMM_IMAGE_TAG)
KMM_WEBHOOK_IMAGE := $(KMM_IMAGE_PREFIX)/$(KMM_WEBHOOK_PATH):$(KMM_IMAGE_TAG)
KMM_WORKER_IMAGE := $(KMM_IMAGE_PREFIX)/$(KMM_WORKER_PATH):$(KMM_IMAGE_TAG)
KMM_SIGN_IMAGE := $(KMM_IMAGE_PREFIX)/$(KMM_SIGN_PATH):$(KMM_IMAGE_TAG)
KMM_BUILD_IMAGE := $(KMM_IMAGE_PREFIX)/$(KMM_KANIKO_PATH):$(KMM_KANIKO_VERSION)
# The kustomize default overlay deploys into this namespace with these Deployment/container names (KMM
# v2.7.0). kmm-install-mirrored targets them directly, so a rename upstream would need updating here.
KMM_NAMESPACE := kmm-operator-system
KMM_CONTROLLER_DEPLOY := kmm-operator-controller
KMM_CONTROLLER_CONTAINER := manager
KMM_WEBHOOK_DEPLOY := kmm-operator-webhook
KMM_WEBHOOK_CONTAINER := webhook-server

KIND_CLUSTER_NAME ?= kasm-e2e
E2E_NAMESPACE ?= kasm-e2e
E2E_RELEASE ?= kasm-e2e
E2E_MARK ?= e2e
E2E_CLUSTER_WARMUP_SECONDS ?= 10
E2E_DNS_RETRIES ?= 2
E2E_DNS_BACKOFF_SECONDS ?= 10
# Full api image reference (repo[:tag]) to use for e2e runs in place of the
# chart's values.yaml default. Applied to both kind-load-images (so the image
# is pulled/loaded into kind) and the helm install/upgrade calls
# (tests/e2e/helpers.py::api_image_override_args). Leave empty for the default.
KASM_API_IMAGE ?=
# Pause between scenarios in `make e2e` to let cluster state settle
# (CoreDNS, kube-proxy, endpoints controller) before the next install.
E2E_SCENARIO_SETTLE_SECONDS ?= 30

# Branch to source the "previous version" chart from for upgrade tests.
# The pytest container has no access to the git repo, so the Makefile
# extracts the chart on the host and bind-mounts it into the container.
OLD_CHART_BRANCH ?= release/1.18.1
OLD_CHART_HOST_DIR := $(CURDIR)/.e2e-old-chart
# In 1.18.x the chart lives at charts/kasm.  Update this if the upgrade
# baseline ever moves to a chart that uses charts/kasm-helm.

# Scenarios are derived from tests/values/*.yaml (basename)
SCENARIOS ?= $(patsubst $(TEST_VALUES_DIR)/%.yaml,%,$(wildcard $(TEST_VALUES_DIR)/*.yaml))

KYN_POLICIES ?= \
  tests/kyverno/pod-security.baseline.yaml \
  tests/kyverno/no-host-namespaces.yaml \
  tests/kyverno/resources.required.enforce.yaml \
  tests/kyverno/probes.required.yaml

# Chart directory used by `kind-load-images` to discover the image list.
# Defaults to the current chart; `kind-load-old-images` overrides this to
# point at the extracted previous-version chart.
KIND_LOAD_CHART_DIR ?= $(CHART_DIR)

# Extra images required by e2e tests but not referenced by the chart itself:
#   postgres:16        external-DB scenario (tests/e2e/start_external_postgres.sh)
#   nginx:1.30-alpine  trusted-CA scenario (tests/e2e/test_02_trusted_ca.py)
KIND_EXTRA_IMAGES ?= postgres:16 nginx:1.30-alpine


UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_S),Darwin)
  OS := darwin
else
  OS := linux
endif

ifeq ($(UNAME_M),x86_64)
  ARCH := amd64
else ifeq ($(UNAME_M),arm64)
  ARCH := arm64
else ifeq ($(UNAME_M),aarch64)
  ARCH := arm64
else
  $(error Unsupported architecture: $(UNAME_M))
endif

CLOUD_PROVIDER_KIND_VERSION_NUM := $(patsubst v%,%,$(CLOUD_PROVIDER_KIND_VERSION))
CLOUD_PROVIDER_KIND_OS := $(OS)
CLOUD_PROVIDER_KIND_ARCH := $(ARCH)

# crane uses capitalised OS and x86_64 instead of amd64
ifeq ($(OS),darwin)
  CRANE_OS := Darwin
else
  CRANE_OS := Linux
endif
CRANE_ARCH := $(subst amd64,x86_64,$(ARCH))
CLOUD_PROVIDER_KIND_PID_FILE ?= $(CURDIR)/.kind/cloud-provider-kind.pid
CLOUD_PROVIDER_KIND_LOG ?= $(CURDIR)/.kind/cloud-provider-kind.log

.PHONY: tools lint render kubeconform kyverno unittest readme readme-check readme-all readme-check-all set-version changelog changelog-llm changelog-console changelog-console-llm changelog-check changelog-check-all docs linkcheck images-check test build-pytest kind-up kind-down kind-recreate kind-ensure kind-load-images kind-load-old-images kind-clean-namespace kind-prep pytest-docker e2e e2e-basic e2e-trustedca e2e-multizone e2e-externaldb e2e-backup e2e-backup-pss e2e-pss e2e-json-logging e2e-upgrade e2e-upgrade-included e2e-upgrade-standalone e2e-settle e2e-preseed validate-preseed extract-old-chart clean deps-agent lint-agent unittest-agent crds-sync-check version-check-agent rancher-check render-agent package-agent package-agent-all images-agent kmm-install kmm-install-mirrored kmm-uninstall

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "; printf "\nUsage: make \033[36m<target>\033[0m\n"} \
	  /^[[:alnum:]_-]+:.*## / {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2} \
	  /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5)}' $(MAKEFILE_LIST)

##@ Tooling

tools: $(HELM) $(KUBECONFORM) $(KYVERNO) $(KIND) $(KUBECTL) $(CLOUD_PROVIDER_KIND) $(CRANE) $(HELM_DOCS) $(YQ) helm-unittest ## Install all pinned tooling into bin/

$(BIN_DIR):
	@mkdir -p $(BIN_DIR)

$(HELM): | $(BIN_DIR)
	@echo "Installing helm $(HELM_VERSION)"
	@tmp_dir=$$(mktemp -d) && \
	  curl -fsSL -o $$tmp_dir/helm.tgz https://get.helm.sh/helm-$(HELM_VERSION)-$(OS)-$(ARCH).tar.gz && \
	  tar -xzf $$tmp_dir/helm.tgz -C $$tmp_dir && \
	  cp $$tmp_dir/$(OS)-$(ARCH)/helm $(HELM) && \
	  chmod +x $(HELM) && \
	  rm -rf $$tmp_dir

$(KUBECONFORM): | $(BIN_DIR)
	@echo "Installing kubeconform $(KUBECONFORM_VERSION)"
	@tmp_dir=$$(mktemp -d) && \
	  curl -fsSL -o $$tmp_dir/kubeconform.tgz https://github.com/yannh/kubeconform/releases/download/$(KUBECONFORM_VERSION)/kubeconform-$(OS)-$(ARCH).tar.gz && \
	  tar -xzf $$tmp_dir/kubeconform.tgz -C $$tmp_dir && \
	  cp $$tmp_dir/kubeconform $(KUBECONFORM) && \
	  chmod +x $(KUBECONFORM) && \
	  rm -rf $$tmp_dir

$(KYVERNO): | $(BIN_DIR)
	@echo "Installing kyverno CLI $(KYVERNO_VERSION)"
	@tmp_dir=$$(mktemp -d) && \
	  curl -fsSL -o $$tmp_dir/kyverno.tar.gz https://github.com/kyverno/kyverno/releases/download/$(KYVERNO_VERSION)/kyverno-cli_$(KYVERNO_VERSION)_$(OS)_$(UNAME_M).tar.gz && \
	  tar -xzf $$tmp_dir/kyverno.tar.gz -C $$tmp_dir && \
	  cp $$tmp_dir/kyverno $(KYVERNO) && \
	  chmod +x $(KYVERNO) && \
	  rm -rf $$tmp_dir

$(KIND): | $(BIN_DIR)
	@echo "Installing kind $(KIND_VERSION)"
	@curl -fsSL -o $(KIND) https://kind.sigs.k8s.io/dl/$(KIND_VERSION)/kind-$(OS)-$(ARCH) && \
	  chmod +x $(KIND)

$(KUBECTL): | $(BIN_DIR)
	@echo "Installing kubectl $(KUBECTL_VERSION)"
	@curl -fsSL -o $(KUBECTL) https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/$(OS)/$(ARCH)/kubectl && \
	  chmod +x $(KUBECTL)

$(CLOUD_PROVIDER_KIND): | $(BIN_DIR)
	@echo "Installing cloud-provider-kind $(CLOUD_PROVIDER_KIND_VERSION)"
	@tmp_dir=$$(mktemp -d) && \
	  curl -fsSL -o $$tmp_dir/cloud-provider-kind.tgz https://github.com/kubernetes-sigs/cloud-provider-kind/releases/download/$(CLOUD_PROVIDER_KIND_VERSION)/cloud-provider-kind_$(CLOUD_PROVIDER_KIND_VERSION_NUM)_$(CLOUD_PROVIDER_KIND_OS)_$(CLOUD_PROVIDER_KIND_ARCH).tar.gz && \
	  tar -xzf $$tmp_dir/cloud-provider-kind.tgz -C $$tmp_dir && \
	  cp $$tmp_dir/cloud-provider-kind $(CLOUD_PROVIDER_KIND) && \
	  chmod +x $(CLOUD_PROVIDER_KIND) && \
	  rm -rf $$tmp_dir

$(CRANE): | $(BIN_DIR)
	@echo "Installing crane $(CRANE_VERSION)"
	@tmp_dir=$$(mktemp -d) && \
	  curl -fsSL -o $$tmp_dir/crane.tgz https://github.com/google/go-containerregistry/releases/download/$(CRANE_VERSION)/go-containerregistry_$(CRANE_OS)_$(CRANE_ARCH).tar.gz && \
	  tar -xzf $$tmp_dir/crane.tgz -C $$tmp_dir crane && \
	  cp $$tmp_dir/crane $(CRANE) && \
	  chmod +x $(CRANE) && \
	  rm -rf $$tmp_dir

# helm-docs release tarballs use the same OS/ARCH casing pattern as crane
# (Linux/Darwin + x86_64/arm64) and drop the leading v from the version.
$(HELM_DOCS): | $(BIN_DIR)
	@echo "Installing helm-docs $(HELM_DOCS_VERSION)"
	@tmp_dir=$$(mktemp -d) && \
	  version_no_v=$$(echo "$(HELM_DOCS_VERSION)" | sed 's/^v//') && \
	  curl -fsSL -o $$tmp_dir/helm-docs.tgz https://github.com/norwoodj/helm-docs/releases/download/$(HELM_DOCS_VERSION)/helm-docs_$${version_no_v}_$(CRANE_OS)_$(CRANE_ARCH).tar.gz && \
	  tar -xzf $$tmp_dir/helm-docs.tgz -C $$tmp_dir helm-docs && \
	  cp $$tmp_dir/helm-docs $(HELM_DOCS) && \
	  chmod +x $(HELM_DOCS) && \
	  rm -rf $$tmp_dir

# yq ships a single static binary per platform, named yq_<os>_<arch> — no archive to unpack.
$(YQ): | $(BIN_DIR)
	@echo "Installing yq $(YQ_VERSION)"
	@curl -fsSL -o $(YQ) https://github.com/mikefarah/yq/releases/download/$(YQ_VERSION)/yq_$(OS)_$(ARCH) && \
	  chmod +x $(YQ)

$(CURDIR)/.kind:
	mkdir -p $(CURDIR)/.kind

ifeq ($(OS),darwin)
  HELM_UNITTEST_OS := macos
else
  HELM_UNITTEST_OS := $(OS)
endif
HELM_UNITTEST_ARCH := $(ARCH)
# Upstream naming: helm-unittest-<os>-<arch>-<version>.tgz
HELM_UNITTEST_TGZ := helm-unittest-$(HELM_UNITTEST_OS)-$(HELM_UNITTEST_ARCH)-$(patsubst v%,%,$(HELM_UNITTEST_VERSION)).tgz
HELM_UNITTEST_URL := https://github.com/helm-unittest/helm-unittest/releases/download/$(HELM_UNITTEST_VERSION)/$(HELM_UNITTEST_TGZ)
# SHA256 for the release tarball (from upstream downloads page).
HELM_UNITTEST_X86_SHA256       ?= 9761f23d9509c98770c026e019e743b524b57010f4bc29175f78d2582ace0633
HELM_UNITTEST_ARM_SHA256       ?= 1e645d96b36582cd8b9fbd53240110267f14d80aa01137341251c60438bbe6b0
HELM_UNITTEST_MACOS_X86_SHA256 ?= 46413a86ded6bfc70cd704ebac16f8d4a0f36712ae399a5d24e32bc44f96985f
HELM_UNITTEST_MACOS_ARM_SHA256 ?= 6a6b67b3f638f015e09c093b67c7609a07101b971a1a6d6a83d1a7f75861a4b2


helm-unittest: $(HELM)
	@mkdir -p $(HELM_PLUGINS_DIR)
	@if HELM_PLUGINS="$(HELM_PLUGINS_DIR)" $(HELM) plugin list 2>/dev/null | grep -q '^unittest\b'; then \
	  exit 0; \
	fi; \
	if [ -z "$(HELM_UNITTEST_X86_SHA256)" ] && [ -z "$(HELM_UNITTEST_ARM_SHA256)" ]; then \
	  echo "HELM_UNITTEST_X86_SHA256 and HELM_UNITTEST_ARM_SHA256 are required to verify $(HELM_UNITTEST_TGZ)."; \
	  echo "Set HELM_UNITTEST_X86_SHA256 and HELM_UNITTEST_ARM_SHA256 to the release tarball SHA256s."; \
	  exit 1; \
	fi; \
	echo "Installing helm-unittest $(HELM_UNITTEST_VERSION) into $(HELM_PLUGINS_DIR)"; \
	tmp_dir=$$(mktemp -d) && \
	curl -fsSL -o $$tmp_dir/$(HELM_UNITTEST_TGZ) $(HELM_UNITTEST_URL) && \
	if [ "$(HELM_UNITTEST_OS)" = "macos" ] && [ "$(ARCH)" = "amd64" ]; then \
	  expected_sha256="$(HELM_UNITTEST_MACOS_X86_SHA256)"; \
	elif [ "$(HELM_UNITTEST_OS)" = "macos" ] && [ "$(ARCH)" = "arm64" ]; then \
	  expected_sha256="$(HELM_UNITTEST_MACOS_ARM_SHA256)"; \
	elif [ "$(ARCH)" = "amd64" ]; then \
	  expected_sha256="$(HELM_UNITTEST_X86_SHA256)"; \
	elif [ "$(ARCH)" = "arm64" ]; then \
	  expected_sha256="$(HELM_UNITTEST_ARM_SHA256)"; \
	else \
	  echo "Unsupported OS/architecture: $(HELM_UNITTEST_OS)/$(ARCH)"; \
	  exit 1; \
	fi; \
	echo "$$expected_sha256  $$tmp_dir/$(HELM_UNITTEST_TGZ)" | sha256sum -c - && \
	extract_dir=$$tmp_dir/extract && \
	mkdir -p $$extract_dir && \
	tar -xzf $$tmp_dir/$(HELM_UNITTEST_TGZ) -C $$extract_dir && \
	plugin_yaml=$$(find $$extract_dir -type f -name plugin.yaml -print -quit) && \
	if [ -z "$$plugin_yaml" ]; then \
	  echo "Failed to locate plugin.yaml in extracted helm-unittest archive"; \
	  exit 1; \
	fi; \
	src_dir=$$(dirname "$$plugin_yaml") && \
	rm -rf "$(HELM_PLUGINS_DIR)/helm-unittest" && \
	cp -R "$$src_dir" "$(HELM_PLUGINS_DIR)/helm-unittest" && \
	rm -rf $$tmp_dir

##@ Static Analysis

lint: $(HELM) lint-agent ## Lint the primary Helm chart (+ the kasm-agent charts, via lint-agent)
	$(HELM) lint $(CHART_DIR)

render: $(HELM) render-agent ## Render all test scenario values to .rendered/ (+ kasm-agent scenarios, via render-agent)
	@mkdir -p .rendered
	@set -euo pipefail; \
	  for values_file in $(TEST_VALUES_DIR)/*.yaml; do \
	    scenario=$$(basename $$values_file .yaml); \
	    echo "Rendering $$scenario"; \
	    $(HELM) template kasm-test $(CHART_DIR) -n kasm-test -f $$values_file > .rendered/$$scenario.yaml; \
	  done

kubeconform: tools render ## Validate rendered manifests (including kasm-agent, and .rendered-infra/) against Kubernetes schemas
	@set -euo pipefail; \
	  for rendered_manifest in .rendered/*.yaml .rendered-infra/*.yaml; do \
	    echo "kubeconform $$rendered_manifest"; \
	    $(KUBECONFORM) -strict -ignore-missing-schemas -summary $$rendered_manifest; \
	  done

# Scoped to .rendered/ only (unchanged) -- render-agent (pulled in via the render prerequisite
# above) writes its non-privileged scenarios there too, so they get the same PSS baseline gate.
# .rendered-infra/ (the infra.yaml scenario) is deliberately excluded: those manifests contain
# privileged DaemonSets (kasm-node-prep; kasm-egress-installer, which additionally runs with
# hostPID/hostNetwork and so also trips kasm-disallow-host-namespaces; and whatever the
# gpu-operator/nfs-server-provisioner third-party charts render) that are exempt from the
# baseline-PSS gate by design -- kubeconform still validates them (see above), kyverno does not.
kyverno: tools render ## Apply Kyverno policies against rendered manifests
	@set -euo pipefail; \
	  policies="$(KYN_POLICIES)"; \
	  for rendered_manifest in .rendered/*.yaml; do \
	    echo "kyverno $$rendered_manifest"; \
	    $(KYVERNO) apply $$policies -r $$rendered_manifest; \
	  done

unittest: tools unittest-agent ## Run helm-unittest test suites (+ the kasm-agent charts, via unittest-agent)
	HELM_PLUGINS="$(HELM_PLUGINS_DIR)" $(HELM) unittest $(CHART_DIR)

test: lint kubeconform kyverno unittest crds-sync-check version-check-agent rancher-check ## Run full static suite: lint + kubeconform + kyverno + unittest + crds-sync-check + version-check-agent + rancher-check

validate-preseed: tools render ## Validate preseed output against the 1.19.0 schema
	python3 tests/validate_preseed.py \
	  --schema tests/schemas/1_19_0-schema.yaml \
	  --rendered .rendered/preseed-validate.yaml

##@ Kasm Agent Charts

deps-agent: $(HELM) ## Build the kasm-agent and kasm-platform Helm dependencies (needs network access: 3 of kasm-agent's 9 deps are remote -- csi-driver-rclone over OCI, gpu-operator and nfs-server-provisioner over HTTP repos)
	$(HELM) dependency build $(AGENT_CHART_DIR)
	@# Second, and only second: kasm-platform archives $(AGENT_CHART_DIR) from disk, so the line
	@# above has to have staged kasm-agent's own dependencies first.
	$(HELM) dependency build $(PLATFORM_CHART_DIR)

lint-agent: $(HELM) deps-agent ## Lint the kasm-agent subcharts, the CRD-only chart, and the kasm-agent/kasm-platform umbrella charts
	@set -euo pipefail; \
	  for chart_dir in $(AGENT_LOCAL_CHART_DIRS); do \
	    echo "lint $$chart_dir"; \
	    $(HELM) lint $$chart_dir; \
	  done; \
	  echo "lint $(AGENT_CRDS_CHART_DIR)"; \
	  $(HELM) lint $(AGENT_CRDS_CHART_DIR); \
	  echo "lint $(AGENT_CHART_DIR)"; \
	  $(HELM) lint $(AGENT_CHART_DIR); \
	  echo "lint $(PLATFORM_CHART_DIR)"; \
	  $(HELM) lint $(PLATFORM_CHART_DIR)

unittest-agent: tools deps-agent ## Run helm-unittest test suites for the kasm-agent subcharts, the CRD-only chart, and the kasm-agent/kasm-platform umbrella charts
	HELM_PLUGINS="$(HELM_PLUGINS_DIR)" $(HELM) unittest $(AGENT_ALL_CHART_DIRS) $(AGENT_CRDS_CHART_DIR) $(PLATFORM_CHART_DIR)

# The five CRD schemas exist in the tree twice, on purpose -- see the "Why this chart exists"
# section of charts/kasm-agent-crds/README.md:
#
#   $(AGENT_CRDS_SOURCE_DIR)/       Helm's crds/ mechanism, applied before the release manifest is
#                                   validated, so the one-command install of an umbrella chart that
#                                   also creates Agent CRs works.
#   $(AGENT_CRDS_CHART_DIR)/templates/  ordinary templates, so a release owns the CRD lifecycle and
#                                   `helm upgrade` applies schema changes.
#
# Both are synced from config/crd/bases/ in the kasm-agent-operator repo, and a cluster must end up
# with the same schema whichever path installed it. This target fails the build the moment they
# diverge -- regenerating upstream and re-copying into only one of the two is the mistake it exists
# to catch.
#
# Exactly two differences are expected, and are normalised away before the diff:
#   * the per-file header comment, which differs by design (yq's `... comments=""` strips every
#     comment from both sides);
#   * `helm.sh/resource-policy: keep`, which only the templated copy carries -- deleted from that
#     side, and separately asserted to be present so its removal cannot hide inside the normalisation.
crds-sync-check: $(YQ) ## Verify charts/kasm-agent-crds templates carry the same CRD schemas as charts/kasm-agent-operator/crds
	@set -euo pipefail; \
	  drift=0; \
	  for crd_source in $(AGENT_CRDS_SOURCE_DIR)/*.yaml; do \
	    crd_file=$$(basename "$$crd_source"); \
	    crd_template="$(AGENT_CRDS_CHART_DIR)/templates/$$crd_file"; \
	    echo "crds-sync-check $$crd_file"; \
	    if [ ! -f "$$crd_template" ]; then \
	      echo "ERROR: $$crd_template is missing -- $(AGENT_CRDS_CHART_DIR) does not ship $$crd_file."; \
	      drift=1; \
	      continue; \
	    fi; \
	    policy=$$($(YQ) '.metadata.annotations."helm.sh/resource-policy" // "<absent>"' "$$crd_template"); \
	    if [ "$$policy" != "keep" ]; then \
	      echo "ERROR: $$crd_template must annotate helm.sh/resource-policy: keep (found: $$policy)."; \
	      echo "       Without it, 'helm uninstall' deletes the CRD and every custom resource stored in it."; \
	      drift=1; \
	    fi; \
	    if ! diff -u \
	      <($(YQ) '... comments=""' "$$crd_source") \
	      <($(YQ) 'del(.metadata.annotations."helm.sh/resource-policy") | ... comments=""' "$$crd_template"); then \
	      echo ""; \
	      echo "ERROR: $$crd_template has drifted from $$crd_source (diff above, '-' is the operator chart)."; \
	      drift=1; \
	    fi; \
	  done; \
	  for crd_template in $(AGENT_CRDS_CHART_DIR)/templates/*.yaml; do \
	    crd_file=$$(basename "$$crd_template"); \
	    if [ ! -f "$(AGENT_CRDS_SOURCE_DIR)/$$crd_file" ]; then \
	      echo "ERROR: $$crd_template has no counterpart in $(AGENT_CRDS_SOURCE_DIR)/."; \
	      drift=1; \
	    fi; \
	  done; \
	  if [ "$$drift" -ne 0 ]; then \
	    echo ""; \
	    echo "The two copies of the Kasm Agent CRDs are out of sync."; \
	    echo "Re-copy the schema bodies so both match config/crd/bases/ in the kasm-agent-operator repo,"; \
	    echo "keeping each file's own header comment and the templated copy's resource-policy annotation."; \
	    exit 1; \
	  fi; \
	  echo "crds-sync-check: both copies of all 5 CRDs agree."

# The companion to crds-sync-check: that one guards the *content* of the two CRD copies, this one
# guards the *versions* that tie the agent-family charts together. Every file:// dependency in
# $(AGENT_CHART_DIR) and $(PLATFORM_CHART_DIR) pins an exact version by hand, and a pin that falls
# behind the chart it names is only loud some of the time -- `helm dependency build` refuses it, but
# `helm package` against an already-staged charts/ directory exits 0 and embeds the OLD archive, so
# the published umbrella ships the subchart the release was meant to replace. The
# charts/kasm-helm -> charts/kasm-platform pin is the one that goes stale on a schedule: every
# `make readme CHART_VERSION=...` moves it. Also asserts $(AGENT_CRDS_CHART_DIR) and
# charts/kasm-agent-operator carry one version, since they ship one set of CRDs.
#
# `scripts/agent_versions.py --bump <chart> <version>` is the fix: it moves the chart and every pin
# naming it together, dry-run until --write.
version-check-agent: ## Verify every file:// dependency pin matches the version the referenced chart declares
	python3 scripts/agent_versions.py --check

# Rancher's Apps catalog reads three files no other Helm client does: the catalog.cattle.io/*
# annotations in Chart.yaml, app-readme.md and questions.yaml. helm lint, helm template and
# helm-unittest never look at them, and a mistyped `variable` in a question is a form field that
# silently writes a value nothing reads. scripts/rancher_check.py checks the five published charts
# (kasm-platform, kasm-agent, kasm-agent-crds, kasm-egress-installer, kasm-helm): annotation set,
# kubeVersion agreement, the CRD auto-install pairing, and every question path against the chart's
# effective values (its own values.yaml, then the file:// dependency an aliased prefix names).
rancher-check: $(YQ) ## Verify the Rancher catalog packaging of the published charts (annotations, app-readme.md, questions.yaml paths)
	python3 scripts/rancher_check.py

# Scenarios are derived from tests/values-agent/*.yaml (basename), same idiom as SCENARIOS above.
# infra.yaml and kmm.yaml are excluded here and rendered separately below: they are the deliberately-
# privileged cluster-infra scenarios and must land in .rendered-infra/, not .rendered/, so kyverno's
# PSS gate never sees them. infra.yaml turns on nodePrep, videoDevicePlugin, and the 3 remote deps;
# kmm.yaml delegates v4l2loopback to the KMM operator, whose `kmm.sigs.x-k8s.io/v1beta1` Module has no
# schema kubeconform can fetch (it is -ignore-missing-schemas skipped) -- a second reason it belongs in
# the infra dir, and the scenario that makes `images-agent` emit the KMM operator image set.
AGENT_SCENARIOS := $(filter-out infra kmm,$(patsubst $(AGENT_TEST_VALUES_DIR)/%.yaml,%,$(wildcard $(AGENT_TEST_VALUES_DIR)/*.yaml)))

render-agent: deps-agent ## Render all kasm-agent test scenario values to .rendered/ (infra.yaml instead goes to .rendered-infra/)
	@mkdir -p .rendered .rendered-infra
	@set -euo pipefail; \
	  for scenario in $(AGENT_SCENARIOS); do \
	    echo "Rendering agent-$$scenario"; \
	    $(HELM) template kasm-agent-test $(AGENT_CHART_DIR) -n kasm-agent-test --include-crds -f $(AGENT_TEST_VALUES_DIR)/$$scenario.yaml > .rendered/agent-$$scenario.yaml; \
	  done; \
	  echo "Rendering agent-infra"; \
	  $(HELM) template kasm-agent-test $(AGENT_CHART_DIR) -n kasm-agent-test --include-crds -f $(AGENT_TEST_VALUES_DIR)/infra.yaml > .rendered-infra/agent-infra.yaml; \
	  echo "Rendering agent-kmm"; \
	  $(HELM) template kasm-agent-test $(AGENT_CHART_DIR) -n kasm-agent-test --include-crds -f $(AGENT_TEST_VALUES_DIR)/kmm.yaml > .rendered-infra/agent-kmm.yaml
	@# $(AGENT_CRDS_CHART_DIR) has no values and therefore no scenarios -- one standalone render is
	@# the whole chart. It lands in .rendered/ so kubeconform validates the five CRDs and the
	@# kyverno PSS gate sweeps it (trivially: there are no pod specs in a CRD).
	@set -euo pipefail; \
	  echo "Rendering agent-crds"; \
	  $(HELM) template kasm-agent-crds-test $(AGENT_CRDS_CHART_DIR) -n kasm-agent-test > .rendered/agent-crds.yaml

# `helm package` embeds every staged dependency (all 9, the 3 remote ones included) inside the
# archive's charts/ directory, so the resulting dist/kasm-agent-0.1.0.tgz is a self-contained
# artifact: `helm install` from it needs no chart repository and no network. This is the file to
# carry across the airgap -- a git clone is not enough, because installing from a checkout still
# requires `helm dependency build` to fetch the 3 remote deps (their .tgz files are gitignored).
package-agent: deps-agent ## Build the self-contained chart archive for offline/airgapped transfer
	@mkdir -p dist
	$(HELM) package $(AGENT_CHART_DIR) -d dist/

# Everything in $(AGENT_PUBLISH_CHART_DIRS), for the release pipeline rather than for the airgap:
# the kasm-agent umbrella (via package-agent, so its 9 dependencies are embedded), the kasm-platform
# umbrella (2 more), the CRD-only chart, and kasm-egress-installer. The GitLab `helm-build-agent`
# job runs this and keeps dist/ as artifacts; `helm-deploy-agent-docker-hub` pushes each archive.
#
# deps-agent runs first through the package-agent prerequisite, and it has to: `helm package` does
# NOT re-resolve dependencies, so packaging a chart whose charts/ directory is empty (a fresh
# clone) or stale (a pin moved since the last build) produces an archive that is quietly missing or
# quietly wrong rather than one that fails. `version-check-agent` guards the stale half of that.
package-agent-all: package-agent ## Package every publishable agent-family chart into dist/ (kasm-agent + kasm-platform + kasm-agent-crds + kasm-egress-installer)
	@mkdir -p dist
	@set -euo pipefail; \
	  for chart_dir in $(filter-out $(AGENT_CHART_DIR),$(AGENT_PUBLISH_CHART_DIRS)); do \
	    echo "package $$chart_dir"; \
	    $(HELM) package $$chart_dir -d dist/; \
	  done; \
	  echo ""; \
	  echo "dist/ now holds $(words $(AGENT_PUBLISH_CHART_DIRS)) publishable archives:"; \
	  ls -1 dist/*.tgz

# Every image reference the rendered kasm-agent manifests carry, deduped, so they can be mirrored
# into an internal registry ahead of an airgapped install. Each Kasm chart splits its images into
# registry/repository/tag, so redirecting them at a mirror is a values override -- see the
# "Airgapped installation" section of charts/kasm-agent/README.md.
#
# The `[/:]` filter drops the gpu-operator ClusterPolicy's bare component names (driver, dcgm,
# k8s-device-plugin, ...), which are `image:` keys paired with sibling repository/version keys
# rather than complete references.
#
# NOTE: this list is only what the manifests *name*. The gpu-operator pulls a much larger set of
# operand images (driver, container-toolkit, DCGM, MIG manager, ...) at runtime, assembled from its
# own values, so mirroring this list alone is not enough when gpuOperator.enabled=true. Follow
# NVIDIA's air-gapped procedure for those:
# https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/install-gpu-operator-air-gapped.html
# Deliberately NOT the same extractor as images-agent. That target finds references with a
# line-oriented awk over `<anything>image:` keys; this one walks every YAML map structurally
# with yq and takes every string value whose key ends in "image" (image, sidecarImage,
# containerImage, each entry of KasmImagePuller.spec.images, ...). Two independent extractors
# have to agree on the same rendered manifests, so a key shape the awk misses -- the
# sidecarImage case that motivated this target -- fails here instead of in an airgapped
# install. (An earlier version re-ran the identical awk on the identical files and could not
# fail.) The `[/:]` filter matches images-agent's: bare component names in the gpu-operator
# ClusterPolicy are not pull references.
images-check: images-agent $(YQ) ## Verify the image list covers every image the manifests reference (independent yq extractor, cross-checked against images-agent's awk)
	@set -euo pipefail; \
	  missing=0; \
	  for ref in $$($(YQ) eval '.. | select(tag == "!!map") | to_entries[] | select(.key | test("[Ii]mage$$")) | .value | select(tag == "!!str")' \
	      .rendered/agent-*.yaml .rendered-infra/agent-infra.yaml | grep -E '[/:]' | sort -u); do \
	    if ! grep -qxF "$$ref" dist/kasm-agent-images.txt; then \
	      echo "images-check: MISSING from dist/kasm-agent-images.txt: $$ref"; \
	      missing=1; \
	    fi; \
	  done; \
	  if [ "$$missing" = "1" ]; then \
	    echo "images-check: an airgap mirror built from that list would be incomplete."; \
	    exit 1; \
	  fi; \
	  echo "images-check: every image referenced by the rendered manifests is listed ($$(grep -cvE '^#|^$$' dist/kasm-agent-images.txt) refs)."

# The awk below matches any key ENDING in "image" -- image:, sidecarImage:, runtimeImage: --
# not just "image:", and matches it whether the key opens a list item (`- image: ...`, the
# shape of every KasmImagePuller.spec.images entry) or not.  The session proxy's sidecar is
# referenced at Agent.spec.sessionProxy.sidecarImage, so an "image:"-only match silently omitted
# it, and an airgap mirror built from this list produced a session proxy that could not start;
# the list-item form was the second such omission, and `make images-check` is what caught it.
# CRD schema property lines are excluded by the value requirement: they have nothing after the
# colon.
images-agent: render-agent ## List every container image the kasm-agent manifests reference (mirror these for airgap)
	@mkdir -p dist
	@set -euo pipefail; \
	  awk '/^[[:space:]]*(-[[:space:]]+)?[A-Za-z]*[Ii]mage:[[:space:]]/ { ref = $$0; sub(/^[[:space:]]*(-[[:space:]]+)?[A-Za-z]*[Ii]mage:[[:space:]]*/, "", ref); gsub(/["[:space:]]/, "", ref); if (ref ~ /[\/:]/) print ref }' \
	    .rendered/agent-*.yaml .rendered-infra/agent-infra.yaml \
	    | sort -u > dist/kasm-agent-images.txt; \
	  image_count=$$(wc -l < dist/kasm-agent-images.txt | tr -d ' '); \
	  kmm_note=""; \
	  if grep -qsE 'kmm\.sigs\.x-k8s\.io/' .rendered/agent-*.yaml .rendered-infra/*.yaml; then \
	    kmm_note=" (plus the KMM mode section -- a rendered scenario uses method:kmm)"; \
	    { \
	      echo ""; \
	      echo "# ---------------------------------------------------------------------------"; \
	      echo "# KMM mode (only if nodePrep.modules.*.method=kmm)"; \
	      echo "# The Kernel Module Management operator is installed out of band -- 'make kmm-install' or,"; \
	      echo "# for airgap, 'make kmm-install-mirrored KMM_IMAGE_REGISTRY=<mirror>' -- not by any Helm"; \
	      echo "# release, so its images are NOT in the deduped list above. Mirror these whenever a node"; \
	      echo "# delegates a module to KMM. Shown at their upstream $(KMM_UPSTREAM_REGISTRY) paths;"; \
	      echo "# kmm-install-mirrored repoints them at <mirror>/<same-path>. See the KMM offline runbook"; \
	      echo "# in charts/kasm-node-prep/README.md."; \
	      echo "$(KMM_UPSTREAM_REGISTRY)/$(KMM_OPERATOR_PATH):$(KMM_IMAGE_TAG)   # operator (always)"; \
	      echo "$(KMM_UPSTREAM_REGISTRY)/$(KMM_WEBHOOK_PATH):$(KMM_IMAGE_TAG)   # webhook (always)"; \
	      echo "$(KMM_UPSTREAM_REGISTRY)/$(KMM_WORKER_PATH):$(KMM_IMAGE_TAG)   # worker (always; operator env RELATED_IMAGE_WORKER)"; \
	      echo "$(KMM_UPSTREAM_REGISTRY)/$(KMM_KANIKO_PATH):$(KMM_KANIKO_VERSION)   # build/kaniko -- only in-cluster build mode (kmm.build.enabled=true; RELATED_IMAGE_BUILD; pin at your discretion)"; \
	      echo "$(KMM_UPSTREAM_REGISTRY)/$(KMM_SIGN_PATH):$(KMM_IMAGE_TAG)   # sign -- only Secure Boot (kmm.sign.enabled=true; RELATED_IMAGE_SIGN)"; \
	      echo "# Per-kernel prebuilt module images (Mode A, kmm.build.enabled=false) -- you build and mirror these:"; \
	      echo "<your-registry>/<repo>:<kernel-version>  # one per fleet kernel, see KMM offline runbook"; \
	    } >> dist/kasm-agent-images.txt; \
	  fi; \
	  cat dist/kasm-agent-images.txt; \
	  echo ""; \
	  echo "Wrote $$image_count image references to dist/kasm-agent-images.txt$$kmm_note"

##@ Cluster Prerequisites

# KMM is installed once per cluster, out of band from any Helm release: it owns the Module CRD and
# runs the controller that builds the kmod image and loads the module on each node. Applying the
# chart's Module CR without it leaves a resource nothing reconciles.
# The online install. `kubectl apply -k` at the pinned ref, then the operator's five images are
# repinned from the overlay's :latest to $(KMM_IMAGE_TAG) (kaniko to $(KMM_KANIKO_VERSION)) -- see
# kmm-install-mirrored for why that is `kubectl set image` for operator+webhook and `kubectl set env`
# for worker/build/sign. The pinning is not optional: :latest is a rolling CI build of the staging
# registry, and on 2026-09-14 its webhook-server image did not even run on x86_64. The overlay also
# creates a cert-manager Issuer and Certificate for the webhook, so cert-manager must already be
# installed in the cluster; without it the apply fails on those two kinds and the webhook never gets a
# certificate.
kmm-install: $(KUBECTL) ## Install the Kernel Module Management operator at the pinned KMM_VERSION (needs cert-manager) -- the cluster prerequisite for nodePrep.modules.v4l2loopback.method=kmm
	$(KUBECTL) apply -k "$(KMM_KUSTOMIZE_URL)"
	$(KUBECTL) -n $(KMM_NAMESPACE) set image deployment/$(KMM_CONTROLLER_DEPLOY) $(KMM_CONTROLLER_CONTAINER)=$(KMM_UPSTREAM_REGISTRY)/$(KMM_OPERATOR_PATH):$(KMM_IMAGE_TAG)
	$(KUBECTL) -n $(KMM_NAMESPACE) set image deployment/$(KMM_WEBHOOK_DEPLOY) $(KMM_WEBHOOK_CONTAINER)=$(KMM_UPSTREAM_REGISTRY)/$(KMM_WEBHOOK_PATH):$(KMM_IMAGE_TAG)
	$(KUBECTL) -n $(KMM_NAMESPACE) set env deployment/$(KMM_CONTROLLER_DEPLOY) \
	  RELATED_IMAGE_WORKER=$(KMM_UPSTREAM_REGISTRY)/$(KMM_WORKER_PATH):$(KMM_IMAGE_TAG) \
	  RELATED_IMAGE_BUILD=$(KMM_UPSTREAM_REGISTRY)/$(KMM_KANIKO_PATH):$(KMM_KANIKO_VERSION) \
	  RELATED_IMAGE_SIGN=$(KMM_UPSTREAM_REGISTRY)/$(KMM_SIGN_PATH):$(KMM_IMAGE_TAG)

# The airgap-ready install. Same `kubectl apply -k` at the pinned ref as kmm-install, then it rewrites
# the operator's images so nothing points at :latest or (with KMM_IMAGE_REGISTRY set) at an unreachable
# upstream registry. The kustomize overlay tags operator+webhook :latest and sets the operator's
# RELATED_IMAGE_WORKER/BUILD/SIGN env to :latest images; all five are repinned to $(KMM_IMAGE_TAG) (kaniko
# to $(KMM_KANIKO_VERSION)) and, when KMM_IMAGE_REGISTRY is set, repointed at that mirror keeping each
# upstream path suffix (e.g. .../kernel-module-management-worker -> $(KMM_IMAGE_PREFIX)/$(KMM_WORKER_PATH)).
# operator+webhook are container images on the Deployments (kubectl set image); worker/build/sign are
# only ever named by the operator's env, so they are set there (kubectl set env). Mirror the exact set
# `make images-agent` prints under "KMM mode" first. With KMM_IMAGE_REGISTRY unset it still does the
# :latest->$(KMM_IMAGE_TAG) pinning but leaves every image on upstream $(KMM_UPSTREAM_REGISTRY) and warns,
# because that is not enough for a true airgap. See the KMM offline runbook in charts/kasm-node-prep/README.md.
kmm-install-mirrored: $(KUBECTL) ## Install KMM and pin/repoint its 5 images for airgap (needs cert-manager) -- set KMM_IMAGE_REGISTRY=<mirror> (unset: same pinning as kmm-install, images left upstream)
	$(KUBECTL) apply -k "$(KMM_KUSTOMIZE_URL)"
	@if [ -z "$(strip $(KMM_IMAGE_REGISTRY))" ]; then \
	  echo "WARNING: KMM_IMAGE_REGISTRY is unset -- pinning operator/webhook/worker/build/sign off :latest to $(KMM_IMAGE_TAG) but leaving them on upstream $(KMM_UPSTREAM_REGISTRY). This is NOT airgap-ready; mirror the images ('make images-agent') and re-run with KMM_IMAGE_REGISTRY=<mirror>."; \
	fi
	$(KUBECTL) -n $(KMM_NAMESPACE) set image deployment/$(KMM_CONTROLLER_DEPLOY) $(KMM_CONTROLLER_CONTAINER)=$(KMM_OPERATOR_IMAGE)
	$(KUBECTL) -n $(KMM_NAMESPACE) set image deployment/$(KMM_WEBHOOK_DEPLOY) $(KMM_WEBHOOK_CONTAINER)=$(KMM_WEBHOOK_IMAGE)
	$(KUBECTL) -n $(KMM_NAMESPACE) set env deployment/$(KMM_CONTROLLER_DEPLOY) \
	  RELATED_IMAGE_WORKER=$(KMM_WORKER_IMAGE) \
	  RELATED_IMAGE_BUILD=$(KMM_BUILD_IMAGE) \
	  RELATED_IMAGE_SIGN=$(KMM_SIGN_IMAGE)

# Deleting the operator stops reconciliation; it does not undo it. Modules KMM has already loaded
# stay loaded on the nodes until they are rmmod'd or the node reboots. To actually unload one,
# delete its Module custom resource *first* (KMM unloads on delete), then remove the operator.
kmm-uninstall: $(KUBECTL) ## Remove the KMM operator -- leaves already-loaded kernel modules on the nodes; delete the Module CR first to unload them
	$(KUBECTL) delete -k "$(KMM_KUSTOMIZE_URL)"

##@ Docs

# Optional extra arguments passed to changelog-draft.py. Override on the
# command line: make changelog-llm CHANGELOG_ARGS="--model claude-sonnet-4-6"
CHANGELOG_ARGS ?=

# Optional: bump the chart/app version everywhere before regenerating docs.
# make readme CHART_VERSION=1.1190.2                  -> APP_VERSION derived as 1.19.0
# make readme CHART_VERSION=1.1200.0-develop          -> APP_VERSION derived as develop
# make readme CHART_VERSION=1.1190.2 APP_VERSION=x.y.z -> APP_VERSION forced, skipping derivation
CHART_VERSION ?=
APP_VERSION ?=

readme: $(HELM_DOCS) ## Regenerate charts/kasm-helm/README.md (+ optionally bump CHART_VERSION/APP_VERSION everywhere)
	@if [ -n "$(CHART_VERSION)" ]; then \
	  python3 scripts/set_versions.py --chart-version "$(CHART_VERSION)" $(if $(APP_VERSION),--app-version "$(APP_VERSION)",); \
	fi
	cd $(CHART_DIR) && $(HELM_DOCS) $(HELM_DOCS_TEMPLATES_FROM_CHART)

# One release bump across every chart in the repo -- the self-maintaining counterpart to
# `make readme CHART_VERSION=...`, which moves only kasm-helm. In order: kasm-helm moves on the Kasm
# Workspaces release scheme (scripts/set_versions.py: version -> appVersion -> README badges ->
# useImageTags); scripts/agent_versions.py --align sets the agent-family and umbrella charts, and
# every file:// pin, to that same version; every README is regenerated; and the vendored dependency
# archives + Chart.lock files are rebuilt so charts/*/charts/ names the new version. `make
# version-check-agent` passes afterwards because every version agrees.
set-version: $(HELM) $(HELM_DOCS) ## Bump EVERY chart to CHART_VERSION (kasm-helm scheme + agent-family aligned to it) and regenerate READMEs + deps
	@if [ -z "$(CHART_VERSION)" ]; then \
	  echo "Usage: make set-version CHART_VERSION=1.1201.0-develop [APP_VERSION=develop]"; exit 2; \
	fi
	python3 scripts/set_versions.py --chart-version "$(CHART_VERSION)" $(if $(APP_VERSION),--app-version "$(APP_VERSION)",)
	python3 scripts/agent_versions.py --align --write
	$(HELM_DOCS) --chart-search-root charts $(HELM_DOCS_TEMPLATES_FROM_ROOT)
	$(HELM) dependency update $(AGENT_CHART_DIR)
	$(HELM) dependency update $(PLATFORM_CHART_DIR)
	@echo ""
	@echo "set-version: every chart is now $(CHART_VERSION). Update the CHANGELOGs (make changelog-check-all) and run 'make test'."

# Fails (non-zero exit) if the committed README.md files are out of date:
#   - charts/kasm-helm/README.md vs. values.yaml + README.md.gotmpl (helm-docs)
#   - README.md version badges/install snippets/"This branch" line vs. Chart.yaml
# Run `make readme CHART_VERSION=...` locally to fix. Wired into the GitLab CI docs-check job.
readme-check: $(HELM_DOCS) ## Verify both README.md files are up to date (use `make readme` to regen)
	@set -euo pipefail; \
	tmp_dir=$$(mktemp -d); \
	trap 'rm -rf "$$tmp_dir"' EXIT; \
	cp $(CHART_DIR)/README.md $$tmp_dir/README.md.before; \
	cd $(CHART_DIR) && $(HELM_DOCS) $(HELM_DOCS_TEMPLATES_FROM_CHART) >/dev/null && cd - >/dev/null; \
	if ! diff -u $$tmp_dir/README.md.before $(CHART_DIR)/README.md > $$tmp_dir/diff; then \
	  echo ""; \
	  echo "ERROR: $(CHART_DIR)/README.md is out of date with values.yaml + README.md.gotmpl."; \
	  echo "Run 'make readme' to regenerate, then commit the result."; \
	  echo ""; \
	  echo "Drift (committed -> regenerated):"; \
	  cat $$tmp_dir/diff; \
	  cp $$tmp_dir/README.md.before $(CHART_DIR)/README.md; \
	  exit 1; \
	fi
	python3 scripts/set_versions.py --check


# Regenerates README.md for every chart in the repo (kasm-helm + all 9 kasm-agent-family charts) in
# a single helm-docs pass. --chart-search-root recursively discovers every directory under charts/
# that has a Chart.yaml, so this needs no per-chart loop and automatically picks up future charts.
# Unlike `readme`, this has no CHART_VERSION/APP_VERSION coupling of its own -- kasm-helm's release
# bump is scripts/set_versions.py, and the agent-family charts are aligned to that version by
# scripts/agent_versions.py --align. `make set-version CHART_VERSION=...` chains both with this
# regeneration; this target on its own just refreshes every README from values.yaml + README.md.gotmpl.
readme-all: $(HELM_DOCS) ## Regenerate README.md for every chart (kasm-helm + all kasm-agent-family charts) from its values.yaml + README.md.gotmpl
	$(HELM_DOCS) --chart-search-root charts $(HELM_DOCS_TEMPLATES_FROM_ROOT)

# Same drift-detection idiom as readme-check (snapshot -> regenerate in place -> diff -> restore on
# failure), just looped across $(ALL_CHART_DIRS) instead of a single chart. Regeneration itself is
# still the one-pass `--chart-search-root charts` from readme-all, so a chart whose README.md.gotmpl
# references another chart's values (none currently do) would still be caught. This is the drift
# guard the 9 kasm-agent-family charts lack today -- readme-check only covers $(CHART_DIR).
readme-check-all: $(HELM_DOCS) ## Verify every chart's README.md is up to date (use `make readme-all` to regen)
	@set -euo pipefail; \
	tmp_dir=$$(mktemp -d); \
	trap 'rm -rf "$$tmp_dir"' EXIT; \
	for chart_dir in $(ALL_CHART_DIRS); do \
	  cp "$$chart_dir/README.md" "$$tmp_dir/$$(basename $$chart_dir).README.md.before"; \
	done; \
	$(HELM_DOCS) --chart-search-root charts $(HELM_DOCS_TEMPLATES_FROM_ROOT) >/dev/null; \
	drift=0; \
	for chart_dir in $(ALL_CHART_DIRS); do \
	  before="$$tmp_dir/$$(basename $$chart_dir).README.md.before"; \
	  if ! diff -u "$$before" "$$chart_dir/README.md" > "$$tmp_dir/$$(basename $$chart_dir).diff"; then \
	    echo ""; \
	    echo "ERROR: $$chart_dir/README.md is out of date with values.yaml + README.md.gotmpl."; \
	    echo "Drift (committed -> regenerated):"; \
	    cat "$$tmp_dir/$$(basename $$chart_dir).diff"; \
	    cp "$$before" "$$chart_dir/README.md"; \
	    drift=1; \
	  fi; \
	done; \
	if [ "$$drift" -ne 0 ]; then \
	  echo ""; \
	  echo "Run 'make readme-all' to regenerate, then commit the result."; \
	  exit 1; \
	fi; \
	echo "readme-check-all: all $(words $(ALL_CHART_DIRS)) chart READMEs are up to date."

changelog: ## Generate or refresh the [Unreleased] scaffold in CHANGELOG.md (annotated with affected components)
	python3 scripts/changelog-draft.py $(CHANGELOG_ARGS)

changelog-llm: tools ## Generate CHANGELOG.md entries via Claude Code CLI with rendered helm diffs (requires `claude` in PATH)
	python3 scripts/changelog-draft.py --use-llm $(CHANGELOG_ARGS)

changelog-console: ## Print full resulting CHANGELOG.md to stdout without writing to disk (safe preview)
	python3 scripts/changelog-draft.py --dry-run $(CHANGELOG_ARGS)

changelog-console-llm: tools ## Print full resulting CHANGELOG.md via Claude Code CLI to stdout without writing to disk (requires `claude` in PATH)
	python3 scripts/changelog-draft.py --use-llm --dry-run $(CHANGELOG_ARGS)

# Fails (non-zero exit) if CHANGELOG.md has not changed relative to BASE_BRANCH
# (default: develop). Skips silently on develop and release/* branches.
# Run `make changelog` locally to generate a scaffold, edit it, then commit.
changelog-check: ## Verify CHANGELOG.md has been updated relative to BASE_BRANCH (default: develop)
	@set -euo pipefail; \
	branch="$${CI_COMMIT_REF_NAME:-$$(git rev-parse --abbrev-ref HEAD)}"; \
	if [[ "$$branch" == "develop" || "$$branch" =~ ^release/ ]]; then \
	  echo "Integration branch ($$branch) — skipping changelog check."; \
	  exit 0; \
	fi; \
	base="$${BASE_BRANCH:-develop}"; \
	git fetch origin "$$base" 2>/dev/null || true; \
	if git diff --name-only "origin/$$base...HEAD" | grep -q "^charts/kasm-helm/CHANGELOG.md$$"; then \
	  echo "CHANGELOG.md updated — check passed."; \
	else \
	  echo ""; \
	  echo "ERROR: charts/kasm-helm/CHANGELOG.md has not been updated."; \
	  echo "Run 'make changelog' to generate a draft, edit it, then commit."; \
	  echo ""; \
	  exit 1; \
	fi

# Per-chart generalization of changelog-check, covering $(ALL_CHART_DIRS) (kasm-helm + all 9
# kasm-agent-family charts) instead of just charts/kasm-helm. For each chart, if this branch touches
# any file under that chart's directory relative to BASE_BRANCH, that chart's own CHANGELOG.md must
# be part of the same diff -- one miss anywhere fails the whole check, with every miss reported
# together rather than stopping at the first. Same develop/release/* skip as changelog-check, since
# those are integration targets where diffing against themselves is meaningless.
changelog-check-all: ## Verify every touched chart's CHANGELOG.md has been updated relative to BASE_BRANCH (default: develop)
	@set -euo pipefail; \
	branch="$${CI_COMMIT_REF_NAME:-$$(git rev-parse --abbrev-ref HEAD)}"; \
	if [[ "$$branch" == "develop" || "$$branch" =~ ^release/ ]]; then \
	  echo "Integration branch ($$branch) — skipping changelog check."; \
	  exit 0; \
	fi; \
	base="$${BASE_BRANCH:-develop}"; \
	git fetch origin "$$base" 2>/dev/null || true; \
	changed="$$(git diff --name-only "origin/$$base...HEAD")"; \
	failed=0; \
	for chart_dir in $(ALL_CHART_DIRS); do \
	  other_changes="$$(printf '%s\n' "$$changed" | grep "^$$chart_dir/" | grep -v "^$$chart_dir/CHANGELOG.md$$" || true)"; \
	  if [ -z "$$other_changes" ]; then \
	    continue; \
	  fi; \
	  if printf '%s\n' "$$changed" | grep -q "^$$chart_dir/CHANGELOG.md$$"; then \
	    echo "$$chart_dir/CHANGELOG.md updated — check passed."; \
	  else \
	    echo "ERROR: $$chart_dir changed but $$chart_dir/CHANGELOG.md was not updated."; \
	    failed=1; \
	  fi; \
	done; \
	if [ "$$failed" -ne 0 ]; then \
	  echo ""; \
	  echo "Run 'make changelog' (or edit the chart's CHANGELOG.md directly) and commit."; \
	  echo ""; \
	  exit 1; \
	fi

linkcheck: ## Check every relative markdown link and anchor across docs/ and the chart READMEs
	python3 scripts/linkcheck.py

docs: readme changelog ## Regenerate README.md and refresh the CHANGELOG.md scaffold

##@ Kind Cluster

kind-up: tools $(CURDIR)/.kind ## Create the kind cluster
	@# Ensure the "kind" docker network has a user-configured subnet.
	@# Required by start_external_postgres.sh's --ip pinning (used by
	@# the standalone-DB upgrade test) — Docker rejects --ip on networks
	@# without an explicit subnet.  kind reuses an existing "kind"
	@# network if present.  No-op if the network already exists.
	@if ! docker network inspect kind >/dev/null 2>&1; then \
	  docker network create --driver bridge --subnet 172.30.0.0/16 kind; \
	fi
	@# Force a clean cluster: a previous CI job killed before kind-down
	@# can leave a dirty cluster behind, which kind-ensure would then
	@# happily reuse.  Per-job dind isolation makes this safe even with
	@# concurrent jobs.
	@if $(KIND) get clusters 2>/dev/null | grep -q "^$(KIND_CLUSTER_NAME)$$"; then \
	  echo "Removing pre-existing kind cluster '$(KIND_CLUSTER_NAME)' for a clean run"; \
	  $(KIND) delete cluster --name $(KIND_CLUSTER_NAME); \
	fi
	$(KIND) create cluster \
	  --name $(KIND_CLUSTER_NAME) \
	  --config tests/e2e/kind-config.yaml \
	  --kubeconfig $(KIND_KUBECONFIG)
	@if [ "$(KIND_INTERNAL_KUBECONFIG)" = "true" ]; then \
	  $(KIND) get kubeconfig --name $(KIND_CLUSTER_NAME) > $(KIND_KUBECONFIG); \
	fi
	@$(MAKE) kind-fix-kubeconfig
	@set -euo pipefail; \
	api_server_url=$$(grep -m1 'server:' $(KIND_KUBECONFIG) | awk '{print $$2}'); \
	if [ -n "$$api_server_url" ]; then \
	  for i in $$(seq 1 60); do \
	    if curl -ksf "$$api_server_url/healthz" >/dev/null 2>&1; then \
	      break; \
	    fi; \
	    sleep 2; \
	  done; \
	fi
	@set -euo pipefail; \
	for i in $$(seq 1 30); do \
	  if $(KUBECTL) --kubeconfig $(KIND_KUBECONFIG) cluster-info >/dev/null 2>&1; then \
	    break; \
	  fi; \
	  sleep 2; \
	done; \
	echo "Kubeconfig server:"; \
	grep -n "server:" $(KIND_KUBECONFIG) || true; \
	$(KUBECTL) --kubeconfig $(KIND_KUBECONFIG) cluster-info

kind-down: ## Destroy the kind cluster
	@if [ -f $(KIND) ]; then \
		if $(KIND) get clusters 2>/dev/null | grep -q "^$(KIND_CLUSTER_NAME)"; then \
			if [ -f "$(CLOUD_PROVIDER_KIND_PID_FILE)" ]; then \
				pid=$$(cat "$(CLOUD_PROVIDER_KIND_PID_FILE)"); \
				kill "$$pid" >/dev/null 2>&1 || true; \
				rm -f "$(CLOUD_PROVIDER_KIND_PID_FILE)"; \
			fi; \
			$(KIND) delete cluster --name $(KIND_CLUSTER_NAME); \
		fi; \
	fi

kind-recreate: ## Destroy and recreate the kind cluster
	$(MAKE) kind-down
	$(MAKE) kind-up

kind-ensure: tools $(CURDIR)/.kind ## Create kind cluster if it does not exist
	@set -euo pipefail; \
	if $(KIND) get clusters | grep -q "^$(KIND_CLUSTER_NAME)$$"; then \
		echo "Kind cluster '$(KIND_CLUSTER_NAME)' already exists"; \
		$(KIND) get kubeconfig --name $(KIND_CLUSTER_NAME) > $(KIND_KUBECONFIG); \
	else \
		$(MAKE) kind-up; \
	fi

build-pytest: ## Build the pytest e2e Docker image
	docker build \
	  -t $(PYTEST_IMAGE) \
	  -f tests/e2e/Dockerfile \
	  tests/e2e

pytest-docker:
	@set -euo pipefail; \
	add_host_arg=""; \
	if getent hosts docker >/dev/null 2>&1; then \
	  docker_ip=$$(getent hosts docker | awk '{print $$1}' | head -n1); \
	  if [ -n "$$docker_ip" ]; then \
	    add_host_arg="--add-host=kind.kasm.local:$$docker_ip"; \
	  fi; \
	fi; \
	sock_args=""; \
	if [ -n "$(E2E_DOCKER_SOCK)" ]; then \
	  sock_args="-v /var/run/docker.sock:/var/run/docker.sock"; \
	  if [ -e /var/run/docker.sock ]; then \
	    sock_gid=$$(stat -c '%g' /var/run/docker.sock); \
	    sock_args="$$sock_args --group-add $$sock_gid"; \
	  fi; \
	fi; \
	docker run --rm $$add_host_arg \
	  --user "$$(id -u):$$(id -g)" \
	  --network host \
	  --workdir=/e2e \
	  -e KUBECONFIG=/kubeconfig \
	  -e KASM_CHART_DIR=/charts/kasm-helm \
	  -e KASM_NAMESPACE=$(E2E_NAMESPACE) \
	  -e KASM_RELEASE=$(E2E_RELEASE) \
	  -e E2E_SCENARIO=$(E2E_SCENARIO) \
	  -e KASM_TAG=$(KASM_TAG) \
	  -e KASM_API_IMAGE=$(KASM_API_IMAGE) \
	  -e HOME=/tmp \
	  -e PYTHONDONTWRITEBYTECODE=1 \
	  -e E2E_CLUSTER_WARMUP_SECONDS=$(E2E_CLUSTER_WARMUP_SECONDS) \
	  -e E2E_DNS_RETRIES=$(E2E_DNS_RETRIES) \
	  -e E2E_DNS_BACKOFF_SECONDS=$(E2E_DNS_BACKOFF_SECONDS) \
	  -e EXTERNAL_DB_HOST=$(EXTERNAL_DB_HOST) \
	  -e EXTERNAL_DB_PASSWORD=$(EXTERNAL_DB_PASSWORD) \
	  -v $(KIND_KUBECONFIG):/kubeconfig:ro \
	  -v $(CURDIR)/charts:/charts:ro \
	  -v $(CURDIR)/tests/e2e/pytest.ini:/e2e/pytest.ini:ro \
	  -v $(CURDIR)/tests/e2e:/e2e \
	  $(if $(E2E_OLD_CHART_HOST_DIR),-v $(E2E_OLD_CHART_HOST_DIR):/old-chart:ro -e E2E_OLD_CHART_DIR=/old-chart) \
	  $$sock_args \
	  $(PYTEST_IMAGE) $(PYTEST_ARGS) \
	  -m e2e -q \
	  -p no:cacheprovider \
	  -o log_cli=true \
	  -o log_cli_level=INFO \
	  -o log_cli_format='%(asctime)s %(levelname)s %(name)s: %(message)s' \
	  -o log_cli_date_format='%H:%M:%S'

kind-load-images: $(CRANE) $(HELM) ## Pull and load current chart images into kind (slow)
	@$(MAKE) kind-fix-kubeconfig
	@set -euo pipefail; \
	api_image_args=""; \
	api_image="$(KASM_API_IMAGE)"; \
	if [ -n "$$api_image" ] && [ "$(KIND_LOAD_CHART_DIR)" = "$(CHART_DIR)" ]; then \
		case "$$api_image" in \
			*:*) api_image_args="--set components.api.image.repository=$${api_image%:*} --set components.api.image.tag=$${api_image##*:}" ;; \
			*) api_image_args="--set components.api.image.repository=$$api_image" ;; \
		esac; \
	fi; \
	chart_images=$$($(HELM) template kasm $(KIND_LOAD_CHART_DIR) \
		--set publicAddr=kind.kasm.local \
		--set certificate.secretName=kasm-tls \
		$$api_image_args \
		| awk '/^[[:space:]]*image:[[:space:]]/{print $$2}' \
		| sort -u); \
	images="$$chart_images $(KIND_EXTRA_IMAGES)"; \
	load_image_archive() { \
		local archive="$$1"; \
		local image="$$2"; \
		if $(KIND) load image-archive "$$archive" --name $(KIND_CLUSTER_NAME); then \
			return 0; \
		fi; \
		echo "kind load image-archive failed for $$image; falling back to direct containerd import"; \
		mapfile -t nodes < <(docker ps --filter "label=io.x-k8s.kind.cluster=$(KIND_CLUSTER_NAME)" --format '{{.Names}}'); \
		if [ $${#nodes[@]} -eq 0 ]; then \
			echo "No kind nodes found for cluster $(KIND_CLUSTER_NAME)" >&2; \
			return 1; \
		fi; \
		for node in "$${nodes[@]}"; do \
			echo "Importing $$image into $$node"; \
			docker exec -i "$$node" ctr -n k8s.io images import - < "$$archive"; \
		done; \
	}; \
	for image in $$images; do \
		echo "Loading image $$image into kind cluster"; \
		tmp_tar=$$(mktemp /tmp/kind-image-XXXXXX.tar); \
		if ! $(CRANE) pull --platform linux/$(ARCH) $$image $$tmp_tar; then \
			rm -f $$tmp_tar; \
			exit 1; \
		fi; \
		if ! load_image_archive "$$tmp_tar" "$$image"; then \
			rm -f $$tmp_tar; \
			exit 1; \
		fi; \
		rm -f $$tmp_tar; \
	done

kind-clean-namespace: ## Delete E2E_NAMESPACE from kind and wait for removal
	@$(MAKE) kind-fix-kubeconfig
	@# Delete PVCs explicitly before the namespace.  Namespace deletion
	@# cascades to PVCs, but we've seen postgres-init flakes when stale
	@# data from a previous run survived on the local-path-provisioner
	@# volume — the new install detects /var/lib/postgresql/data as
	@# already-initialised and skips data.sql, leaving the schema empty
	@# enough that api init containers spin forever waiting on `zones`.
	@# Waiting on PVC delete forces the on-disk directories to be
	@# released before we move on.
	$(KUBECTL) --kubeconfig $(KIND_KUBECONFIG) delete pvc --all -n $(E2E_NAMESPACE) --ignore-not-found --wait=true --timeout=120s || true
	$(KUBECTL) --kubeconfig $(KIND_KUBECONFIG) delete namespace $(E2E_NAMESPACE) --ignore-not-found
	$(KUBECTL) --kubeconfig $(KIND_KUBECONFIG) wait --for=delete namespace/$(E2E_NAMESPACE) --timeout=300s || true

kind-prep: kind-ensure kind-load-images kind-clean-namespace ## Prepare kind for a scenario: ensure cluster, load images, clean namespace

# Pause between scenarios in the umbrella target so the cluster has
# time to clean up the previous namespace before the next install starts.
# Reduces back-to-back flakes (see E2E_SCENARIO_SETTLE_SECONDS).
##@ End-to-End Tests

e2e-settle: ## Pause between scenarios to let cluster state settle
	@echo "[e2e] settling for $(E2E_SCENARIO_SETTLE_SECONDS)s before next scenario..."
	@sleep $(E2E_SCENARIO_SETTLE_SECONDS)

e2e: ## Run all e2e scenarios sequentially (requires kind cluster)
	$(MAKE) e2e-basic E2E_NAMESPACE=kasm-e2e-basic
	$(MAKE) kind-clean-namespace E2E_NAMESPACE=kasm-e2e-basic
	$(MAKE) e2e-settle
	$(MAKE) e2e-trustedca E2E_NAMESPACE=kasm-e2e-trustedca
	$(MAKE) kind-clean-namespace E2E_NAMESPACE=kasm-e2e-trustedca
	$(MAKE) e2e-settle
	$(MAKE) e2e-multizone E2E_NAMESPACE=kasm-e2e-multizone
	$(MAKE) kind-clean-namespace E2E_NAMESPACE=kasm-e2e-multizone
	$(MAKE) e2e-settle
	$(MAKE) e2e-externaldb E2E_NAMESPACE=kasm-e2e-externaldb
	$(MAKE) kind-clean-namespace E2E_NAMESPACE=kasm-e2e-externaldb
	$(MAKE) e2e-settle
	$(MAKE) e2e-backup-pss E2E_NAMESPACE=kasm-e2e-backup-pss
	$(MAKE) kind-clean-namespace E2E_NAMESPACE=kasm-e2e-backup-pss
	$(MAKE) e2e-settle
	$(MAKE) e2e-backup E2E_NAMESPACE=kasm-e2e-backup
	$(MAKE) kind-clean-namespace E2E_NAMESPACE=kasm-e2e-backup
	$(MAKE) e2e-settle
	$(MAKE) e2e-pss E2E_NAMESPACE=kasm-e2e-pss
	$(MAKE) kind-clean-namespace E2E_NAMESPACE=kasm-e2e-pss
	$(MAKE) e2e-settle
	$(MAKE) e2e-json-logging E2E_NAMESPACE=kasm-e2e-json-logging
	$(MAKE) kind-clean-namespace E2E_NAMESPACE=kasm-e2e-json-logging
	$(MAKE) e2e-settle
	$(MAKE) e2e-upgrade-included E2E_NAMESPACE=kasm-e2e-upgrade-included
	$(MAKE) kind-clean-namespace E2E_NAMESPACE=kasm-e2e-upgrade-included
	$(MAKE) e2e-settle
	$(MAKE) e2e-upgrade-standalone E2E_NAMESPACE=kasm-e2e-upgrade-standalone
	$(MAKE) kind-clean-namespace E2E_NAMESPACE=kasm-e2e-upgrade-standalone
	$(MAKE) e2e-settle
	$(MAKE) e2e-preseed E2E_NAMESPACE=kasm-e2e-preseed
	$(MAKE) kind-clean-namespace E2E_NAMESPACE=kasm-e2e-preseed
	@# Final cleanup of host-side artefacts left behind by the
	@# external-postgres-using tests (e2e-externaldb, e2e-upgrade-standalone)
	@# and the chart-extraction step from e2e-upgrade-*.
	@./tests/e2e/stop_external_postgres.sh
	@rm -rf $(OLD_CHART_HOST_DIR)

e2e-basic: kind-prep build-pytest ## Basic install and login page verification
	$(MAKE) pytest-docker E2E_SCENARIO=e2e-basic PYTEST_ARGS="test_01_basic_deploy.py"

e2e-trustedca: kind-prep build-pytest ## Install with custom CA bundle
	$(MAKE) pytest-docker E2E_SCENARIO=e2e-trustedca PYTEST_ARGS="-m e2e -q test_02_trusted_ca.py"

e2e-multizone: kind-prep build-pytest ## Multi-zone topology with ingress-nginx
	@export PATH="$(BIN_DIR):$$PATH" && \
	export KUBECONFIG=$(KIND_KUBECONFIG) && \
	export CLOUD_PROVIDER_KIND=$(CLOUD_PROVIDER_KIND) && \
	export CLOUD_PROVIDER_KIND_PID_FILE=$(CLOUD_PROVIDER_KIND_PID_FILE) && \
	export CLOUD_PROVIDER_KIND_LOG=$(CLOUD_PROVIDER_KIND_LOG) && \
	./tests/e2e/install_ingress_nginx.sh && \
	$(MAKE) pytest-docker E2E_SCENARIO=e2e-multizone PYTEST_ARGS="-m e2e -q test_03_multizone_ingress.py"

# The external-DB tests run a postgres container outside kind on the dind
# host.  We trap EXIT so the container + data volumes are torn down even
# when pytest fails — without the trap, a failed run leaves the postgres
# container behind and (when running locally or on a runner that reuses
# dind) the next invocation collides with stale data on its volume.
e2e-externaldb: kind-prep build-pytest ## Install against an external standalone Postgres
	@set -e; \
	./tests/e2e/stop_external_postgres.sh; \
	trap './tests/e2e/stop_external_postgres.sh' EXIT; \
	export EXTERNAL_DB_HOST="$$(./tests/e2e/start_external_postgres.sh)"; \
	export EXTERNAL_DB_PASSWORD=$${EXTERNAL_DB_PASSWORD:-postgres}; \
	$(MAKE) pytest-docker E2E_SCENARIO=e2e-externaldb PYTEST_ARGS="-m e2e -q test_04_external_db.py"

e2e-backup: kind-prep build-pytest ## DB backup CronJob test
	$(MAKE) pytest-docker E2E_SCENARIO=e2e-backup PYTEST_ARGS="-m e2e -q test_07_db_backup.py"

e2e-backup-pss: kind-prep build-pytest ## DB backup under Pod Security Standards restricted
	$(MAKE) pytest-docker E2E_SCENARIO=e2e-backup-pss PYTEST_ARGS="-m e2e -q test_08_db_backup_restricted.py"

e2e-pss: kind-prep build-pytest ## Pod Security Standards restricted namespace test
	$(MAKE) pytest-docker E2E_SCENARIO=e2e-pss PYTEST_ARGS="-m e2e -q test_06_pod_security_standards.py"

e2e-preseed: kind-prep build-pytest ## Preseed verification: group, settings, and user seeded via custom_properties.yaml
	$(MAKE) pytest-docker E2E_SCENARIO=e2e-preseed PYTEST_ARGS="-m e2e -q test_11_preseed.py"

e2e-json-logging: kind-prep build-pytest ## Verify all non-Guac pods emit JSON logs when logFormat=json
	$(MAKE) pytest-docker E2E_SCENARIO=e2e-json-logging PYTEST_ARGS="-m e2e -q test_10_json_logging.py"

##@ Upgrade Helpers

extract-old-chart: ## Extract OLD_CHART_BRANCH chart to .e2e-old-chart/
	@rm -rf $(OLD_CHART_HOST_DIR)
	@mkdir -p $(OLD_CHART_HOST_DIR)
	@# GitLab CI shallow-clones only the current ref, so origin/$(OLD_CHART_BRANCH)
	@# typically isn't present.  Fetch (shallow) only when missing so local dev
	@# clones aren't converted to shallow.
	@if ! git rev-parse --verify --quiet origin/$(OLD_CHART_BRANCH) >/dev/null; then \
	  git fetch --depth=1 --no-tags origin $(OLD_CHART_BRANCH); \
	fi
	@git archive origin/$(OLD_CHART_BRANCH) charts/ | tar -x -C $(OLD_CHART_HOST_DIR)
	@echo "Extracted origin/$(OLD_CHART_BRANCH) chart to $(OLD_CHART_HOST_DIR)"

# Pre-load the previous-version chart's images into kind so the Phase 1
# install can use imagePullPolicy=Never (matching the rest of the e2e
# suite).  Reuses kind-load-images by overriding KIND_LOAD_CHART_DIR so the
# pull/import logic stays in one place.
kind-load-old-images: extract-old-chart ## Load OLD_CHART_BRANCH images into kind for upgrade tests
	@$(MAKE) kind-load-images \
	  KIND_LOAD_CHART_DIR="$(OLD_CHART_HOST_DIR)/charts/kasm"

e2e-upgrade-included: kind-prep build-pytest kind-load-old-images ## Upgrade from 1.18.1 with included DB StatefulSet
	$(MAKE) pytest-docker E2E_SCENARIO=e2e-upgrade-included \
	  E2E_OLD_CHART_HOST_DIR=$(OLD_CHART_HOST_DIR) \
	  PYTEST_ARGS="-m e2e -q test_09_db_upgrade.py::test_db_upgrade_included_db"

# Same EXIT trap as e2e-externaldb: the postgres-14 container started for
# the upgrade-from-14 scenario must be torn down on any pytest failure
# so the next run starts from a clean external DB.
e2e-upgrade-standalone: kind-prep build-pytest kind-load-old-images ## Upgrade from 1.18.1 with external Postgres 14→16 swap
	@set -e; \
	./tests/e2e/stop_external_postgres.sh; \
	trap './tests/e2e/stop_external_postgres.sh' EXIT; \
	docker pull tianon/postgres-upgrade:14-to-16 >/dev/null; \
	docker pull postgres:14 >/dev/null; \
	docker pull postgres:16 >/dev/null; \
	export POSTGRES_VERSION=14; \
	export POSTGRES_DATA_VOLUME=kasm-e2e-postgres-data-14; \
	export EXTERNAL_DB_HOST="$$(./tests/e2e/start_external_postgres.sh)"; \
	export EXTERNAL_DB_PASSWORD=$${EXTERNAL_DB_PASSWORD:-postgres}; \
	$(MAKE) pytest-docker E2E_SCENARIO=e2e-upgrade-standalone \
	  E2E_OLD_CHART_HOST_DIR=$(OLD_CHART_HOST_DIR) \
	  E2E_DOCKER_SOCK=true \
	  PYTEST_ARGS="-m e2e -q test_09_db_upgrade.py::test_db_upgrade_standalone_db"

e2e-upgrade: e2e-upgrade-included e2e-upgrade-standalone ## Run both upgrade e2e tests

##@ Maintenance

clean: kind-down ## Remove build artifacts, tooling, rendered output, and kind cluster
	@rm -rf .rendered; \
	rm -rf .rendered-infra; \
	rm -rf dist; \
	rm -rf $(BIN_DIR); \
	rm -rf __pycache__; \
	rm -rf tests/e2e/__pycache__; \
	rm -rf tests/e2e/.pytest_cache; \
	rm -rf .kind; \
	rm -rf .helm; \
	rm -rf charts/kasm-helm/tests/__snapshot__; \
	rm -rf $(OLD_CHART_HOST_DIR); \
	./tests/e2e/stop_external_postgres.sh
