#!/usr/bin/env bash
set -euo pipefail

POSTGRES_CONTAINER_NAME="${POSTGRES_CONTAINER_NAME:-kasm-e2e-postgres}"
docker rm -f "${POSTGRES_CONTAINER_NAME}" >/dev/null 2>&1 || true

# Remove any postgres data volumes left over from upgrade tests.  The
# SSL volume (kasm-e2e-postgres-ssl) is intentionally preserved across
# runs to avoid regenerating self-signed certs each time.
for vol in $(docker volume ls -q --filter 'name=^kasm-e2e-postgres-data-' 2>/dev/null); do
  docker volume rm "${vol}" >/dev/null 2>&1 || true
done
