#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:?KUBECONFIG must be set}"

CLOUD_PROVIDER_KIND="${CLOUD_PROVIDER_KIND:-cloud-provider-kind}"
CLOUD_PROVIDER_KIND_PID_FILE="${CLOUD_PROVIDER_KIND_PID_FILE:-/tmp/cloud-provider-kind.pid}"
CLOUD_PROVIDER_KIND_LOG="${CLOUD_PROVIDER_KIND_LOG:-/tmp/cloud-provider-kind.log}"

if ! command -v "$CLOUD_PROVIDER_KIND" >/dev/null 2>&1; then
  echo "cloud-provider-kind not found. Ensure it is installed and on PATH." >&2
  exit 1
fi

# Start cloud-provider-kind if not already running
if [ -f "$CLOUD_PROVIDER_KIND_PID_FILE" ] && kill -0 "$(cat "$CLOUD_PROVIDER_KIND_PID_FILE")" >/dev/null 2>&1; then
  echo "cloud-provider-kind already running (pid $(cat "$CLOUD_PROVIDER_KIND_PID_FILE"))"
else
  echo "Starting cloud-provider-kind (log: $CLOUD_PROVIDER_KIND_LOG)"
  nohup "$CLOUD_PROVIDER_KIND" > "$CLOUD_PROVIDER_KIND_LOG" 2>&1 &
  echo $! > "$CLOUD_PROVIDER_KIND_PID_FILE"
  sleep 1
fi

# Ensure node is eligible for external load balancer assignment
node_name="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
kubectl label node "$node_name" node.kubernetes.io/exclude-from-external-load-balancers- >/dev/null 2>&1 || true

# No ingress-nginx install needed; cloud-provider-kind handles ingress
