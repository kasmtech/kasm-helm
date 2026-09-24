#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:?KUBECONFIG must be set}"

CLOUD_PROVIDER_KIND_IMAGE="${CLOUD_PROVIDER_KIND_IMAGE:?CLOUD_PROVIDER_KIND_IMAGE must be set}"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kasm-e2e}"
CLOUD_PROVIDER_KIND_CONTAINER="${CLOUD_PROVIDER_KIND_CONTAINER:-cpk-${KIND_CLUSTER_NAME}}"
CLOUD_PROVIDER_KIND_READY_TIMEOUT="${CLOUD_PROVIDER_KIND_READY_TIMEOUT:-90}"

if ! [[ "$CLOUD_PROVIDER_KIND_READY_TIMEOUT" =~ ^[0-9]+$ ]]; then
  echo "CLOUD_PROVIDER_KIND_READY_TIMEOUT must be a whole number of seconds (got '$CLOUD_PROVIDER_KIND_READY_TIMEOUT')" >&2
  exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found. Ensure it is installed and on PATH." >&2
  exit 1
fi

dump_cloud_provider_kind_log() {
  echo "$(date -u +%FT%TZ) ----- begin cloud-provider-kind log ($CLOUD_PROVIDER_KIND_CONTAINER) -----" >&2
  docker logs --tail 500 "$CLOUD_PROVIDER_KIND_CONTAINER" >&2 2>&1 || echo "(unable to read logs for container: $CLOUD_PROVIDER_KIND_CONTAINER)" >&2
  echo "----- end cloud-provider-kind log -----" >&2
}

# Start cloud-provider-kind if not already running
if [ "$(docker inspect -f '{{.State.Running}}' "$CLOUD_PROVIDER_KIND_CONTAINER" 2>/dev/null || true)" = "true" ]; then
  echo "cloud-provider-kind already running (container $CLOUD_PROVIDER_KIND_CONTAINER)"
else
  docker rm -f "$CLOUD_PROVIDER_KIND_CONTAINER" >/dev/null 2>&1 || true
  echo "Starting cloud-provider-kind (container: $CLOUD_PROVIDER_KIND_CONTAINER, image: $CLOUD_PROVIDER_KIND_IMAGE)"
  docker run -d --name "$CLOUD_PROVIDER_KIND_CONTAINER" --network kind \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "$CLOUD_PROVIDER_KIND_IMAGE" >/dev/null
  sleep 1
fi

# Wait for cloud-provider-kind to actually be connected to the cluster. It
# installs the Gateway API CRDs once connected, so the CRD's presence is a
# readiness signal the process can't fake.
elapsed=0
while ! kubectl get crd gateways.gateway.networking.k8s.io --request-timeout=5s >/dev/null 2>&1; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$CLOUD_PROVIDER_KIND_CONTAINER" 2>/dev/null || true)" != "true" ]; then
    echo "$(date -u +%FT%TZ) cloud-provider-kind (container $CLOUD_PROVIDER_KIND_CONTAINER) exited before becoming ready" >&2
    dump_cloud_provider_kind_log
    exit 1
  fi
  if [ "$elapsed" -ge "$CLOUD_PROVIDER_KIND_READY_TIMEOUT" ]; then
    echo "$(date -u +%FT%TZ) timed out after ${elapsed}s waiting for cloud-provider-kind to install the Gateway API CRDs" >&2
    dump_cloud_provider_kind_log
    exit 1
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done
echo "$(date -u +%FT%TZ) cloud-provider-kind ready after ${elapsed}s (Gateway API CRDs present)"

# Ensure node is eligible for external load balancer assignment
node_name="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
kubectl label node "$node_name" node.kubernetes.io/exclude-from-external-load-balancers- >/dev/null 2>&1 || true

# No ingress-nginx install needed; cloud-provider-kind handles ingress
