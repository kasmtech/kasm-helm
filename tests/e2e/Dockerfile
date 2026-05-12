FROM python:3.12-slim

ARG KUBECTL_VERSION=1.29.2
# Pinned to match the documented minimum in README.md ("Helm 3.18.x+").
# Bump in lockstep with the README requirement and the Makefile pin.
ARG HELM_VERSION=3.18.6
# Static docker CLI is used by the standalone-DB upgrade test to swap
# the external postgres container mid-flow.  The daemon socket is
# bind-mounted at runtime by the Makefile only for that scenario.
ARG DOCKER_CLI_VERSION=27.5.1

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      curl ca-certificates bash git && \
    rm -rf /var/lib/apt/lists/*

# kubectl
RUN curl -fsSL https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
    -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

# helm
RUN curl -fsSL https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz | \
    tar -xz && \
    mv linux-amd64/helm /usr/local/bin/helm && \
    chmod +x /usr/local/bin/helm && \
    rm -rf linux-amd64

# docker CLI (no daemon).  Only used when /var/run/docker.sock is
# bind-mounted by the Makefile for the standalone-DB upgrade test.
RUN curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_CLI_VERSION}.tgz" | \
    tar -xz -C /tmp && \
    mv /tmp/docker/docker /usr/local/bin/docker && \
    chmod +x /usr/local/bin/docker && \
    rm -rf /tmp/docker

WORKDIR /e2e

COPY requirements.txt /e2e/requirements.txt
RUN pip install --no-cache-dir -r /e2e/requirements.txt

ENTRYPOINT ["pytest"]
