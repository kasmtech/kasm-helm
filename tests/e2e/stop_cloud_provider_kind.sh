#!/usr/bin/env bash
set -euo pipefail

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kasm-e2e}"
CLOUD_PROVIDER_KIND_CONTAINER="${CLOUD_PROVIDER_KIND_CONTAINER:-cpk-${KIND_CLUSTER_NAME}}"

if docker inspect "${CLOUD_PROVIDER_KIND_CONTAINER}" >/dev/null 2>&1; then
  echo "$(date -u +%FT%TZ) ----- begin cloud-provider-kind log (${CLOUD_PROVIDER_KIND_CONTAINER}) -----" >&2
  docker logs --tail 500 "${CLOUD_PROVIDER_KIND_CONTAINER}" >&2 2>&1 || true
  echo "----- end cloud-provider-kind log -----" >&2
  docker rm -f "${CLOUD_PROVIDER_KIND_CONTAINER}" >/dev/null 2>&1 || true
fi

# cloud-provider-kind starts long-running envoy LoadBalancer containers with
# --restart=on-failure; killing the controller process does not stop them.
for c in $(docker ps -aq --filter "label=io.x-k8s.cloud-provider-kind.cluster=${KIND_CLUSTER_NAME}" 2>/dev/null); do
  docker rm -f "${c}" >/dev/null 2>&1 || true
done
