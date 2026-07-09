SHELL := /usr/bin/env bash

CHART_DIR := charts/kasm-helm
TEST_VALUES_DIR := tests/values

BIN_DIR := $(CURDIR)/bin
HELM := $(BIN_DIR)/helm
KUBECONFORM := $(BIN_DIR)/kubeconform
KYVERNO := $(BIN_DIR)/kyverno
KIND := $(BIN_DIR)/kind
KUBECTL := $(BIN_DIR)/kubectl
CLOUD_PROVIDER_KIND := $(BIN_DIR)/cloud-provider-kind
CRANE := $(BIN_DIR)/crane
HELM_DOCS := $(BIN_DIR)/helm-docs
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

KIND_CLUSTER_NAME ?= kasm-e2e
E2E_NAMESPACE ?= kasm-e2e
E2E_RELEASE ?= kasm-e2e
E2E_MARK ?= e2e
E2E_CLUSTER_WARMUP_SECONDS ?= 10
E2E_DNS_RETRIES ?= 2
E2E_DNS_BACKOFF_SECONDS ?= 10
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

.PHONY: tools lint render kubeconform kyverno unittest readme readme-check changelog changelog-llm changelog-console changelog-console-llm changelog-check docs test build-pytest kind-up kind-down kind-recreate kind-ensure kind-load-images kind-load-old-images kind-clean-namespace kind-prep pytest-docker e2e e2e-basic e2e-trustedca e2e-multizone e2e-externaldb e2e-backup e2e-backup-pss e2e-pss e2e-json-logging e2e-upgrade e2e-upgrade-included e2e-upgrade-standalone e2e-settle extract-old-chart clean

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "; printf "\nUsage: make \033[36m<target>\033[0m\n"} \
	  /^[[:alnum:]_-]+:.*## / {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2} \
	  /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5)}' $(MAKEFILE_LIST)

##@ Tooling

tools: $(HELM) $(KUBECONFORM) $(KYVERNO) $(KIND) $(KUBECTL) $(CLOUD_PROVIDER_KIND) $(CRANE) $(HELM_DOCS) helm-unittest ## Install all pinned tooling into bin/

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

lint: $(HELM) ## Lint the primary Helm chart
	$(HELM) lint $(CHART_DIR)

render: $(HELM) ## Render all test scenario values to .rendered/
	@mkdir -p .rendered
	@set -euo pipefail; \
	  for values_file in $(TEST_VALUES_DIR)/*.yaml; do \
	    scenario=$$(basename $$values_file .yaml); \
	    echo "Rendering $$scenario"; \
	    $(HELM) template kasm-test $(CHART_DIR) -n kasm-test -f $$values_file > .rendered/$$scenario.yaml; \
	  done

kubeconform: tools render ## Validate rendered manifests against Kubernetes schemas
	@set -euo pipefail; \
	  for rendered_manifest in .rendered/*.yaml; do \
	    echo "kubeconform $$rendered_manifest"; \
	    $(KUBECONFORM) -strict -ignore-missing-schemas -summary $$rendered_manifest; \
	  done

kyverno: tools render ## Apply Kyverno policies against rendered manifests
	@set -euo pipefail; \
	  policies="$(KYN_POLICIES)"; \
	  for rendered_manifest in .rendered/*.yaml; do \
	    echo "kyverno $$rendered_manifest"; \
	    $(KYVERNO) apply $$policies -r $$rendered_manifest; \
	  done

unittest: tools ## Run helm-unittest test suites
	HELM_PLUGINS="$(HELM_PLUGINS_DIR)" $(HELM) unittest $(CHART_DIR)

test: lint kubeconform kyverno unittest ## Run full static suite: lint + kubeconform + kyverno + unittest

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
	cd $(CHART_DIR) && $(HELM_DOCS)

# Fails (non-zero exit) if the committed README.md files are out of date:
#   - charts/kasm-helm/README.md vs. values.yaml + README.md.gotmpl (helm-docs)
#   - README.md version badges/install snippets/"This branch" line vs. Chart.yaml
# Run `make readme CHART_VERSION=...` locally to fix. Wired into the GitLab CI docs-check job.
readme-check: $(HELM_DOCS) ## Verify both README.md files are up to date (use `make readme` to regen)
	@set -euo pipefail; \
	tmp_dir=$$(mktemp -d); \
	trap 'rm -rf "$$tmp_dir"' EXIT; \
	cp $(CHART_DIR)/README.md $$tmp_dir/README.md.before; \
	cd $(CHART_DIR) && $(HELM_DOCS) >/dev/null && cd - >/dev/null; \
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
	chart_images=$$($(HELM) template kasm $(KIND_LOAD_CHART_DIR) \
		--set publicAddr=kind.kasm.local \
		--set certificate.secretName=kasm-tls \
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

e2e-pss: kind-prep build-pytest ## Pod Security Standards restricted namespace test
	$(MAKE) pytest-docker E2E_SCENARIO=e2e-pss PYTEST_ARGS="-m e2e -q test_06_pod_security_standards.py"

e2e-json-logging: kind-prep build-pytest ## Verify all non-Guac pods emit JSON logs when logFormat=json
	$(MAKE) pytest-docker E2E_SCENARIO=e2e-json-logging PYTEST_ARGS="-m e2e -q test_10_json_logging.py"

##@ Maintenance

clean: kind-down ## Remove build artifacts, tooling, rendered output, and kind cluster
	@rm -rf .rendered; \
	rm -rf $(BIN_DIR); \
	rm -rf __pycache__; \
	rm -rf tests/e2e/__pycache__; \
	rm -rf tests/e2e/.pytest_cache; \
	rm -rf .kind; \
	rm -rf .helm; \
	rm -rf charts/kasm-helm/tests/__snapshot__; \
	rm -rf $(OLD_CHART_HOST_DIR); \
	./tests/e2e/stop_external_postgres.sh
