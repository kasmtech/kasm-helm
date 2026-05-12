#!/usr/bin/env bash
set -euo pipefail

POSTGRES_CONTAINER_NAME="${POSTGRES_CONTAINER_NAME:-kasm-e2e-postgres}"
POSTGRES_PASSWORD="${EXTERNAL_DB_PASSWORD:-postgres}"
POSTGRES_USER=kasmapp
# Major version of the postgres image to run.  Default 16 keeps existing
# tests (test_04_external_db) on the current version.  The standalone
# upgrade test starts with 14 and later swaps to 16 via
# swap_external_postgres.sh.
POSTGRES_VERSION="${POSTGRES_VERSION:-16}"
SSL_VOLUME="${SSL_VOLUME:-kasm-e2e-postgres-ssl}"
# Optional: pin the container to a specific IP on the kind docker network.
# Unset by default — Docker assigns dynamically (matching test_04 behaviour).
# swap_external_postgres.sh sets this to the previous container's IP so the
# replacement keeps the same address and chart-deployed pods/jobs don't have
# to be re-rendered against a new hostname.
EXTERNAL_DB_FIXED_IP="${EXTERNAL_DB_FIXED_IP:-}"
# Optional: persistent data volume mounted at /var/lib/postgresql/data.
# When set, the database survives container removal — needed by the
# standalone-DB upgrade test for the in-place pg_upgrade to PG16.
# Unset by default (test_04 behaviour: data lives in the container layer
# and is discarded on docker rm).
POSTGRES_DATA_VOLUME="${POSTGRES_DATA_VOLUME:-}"

docker volume create "${SSL_VOLUME}" >/dev/null 2>&1 || true
if [[ -n "${POSTGRES_DATA_VOLUME}" ]]; then
  docker volume create "${POSTGRES_DATA_VOLUME}" >/dev/null 2>&1 || true
fi

if ! docker run --rm -v "${SSL_VOLUME}:/ssl" "postgres:${POSTGRES_VERSION}" bash -c "test -f /ssl/server.crt -a -f /ssl/server.key" >/dev/null 2>&1; then
  # Generate certs inside a postgres container so ownership/permissions match.
  docker run --rm \
    -v "${SSL_VOLUME}:/ssl" \
    "postgres:${POSTGRES_VERSION}" \
    bash -c "set -e; \
      if ! command -v openssl >/dev/null 2>&1; then \
        echo 'openssl not found in postgres image' >&2; exit 1; \
      fi; \
      openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
        -keyout /ssl/server.key \
        -out /ssl/server.crt \
        -subj '/CN=kasm-e2e-postgres' >/dev/null 2>&1; \
      chmod 600 /ssl/server.key; \
      chmod 644 /ssl/server.crt; \
      chown 999:999 /ssl/server.key /ssl/server.crt" >/dev/null 2>&1
fi

# Clean up any old container
docker rm -f "${POSTGRES_CONTAINER_NAME}" >/dev/null 2>&1 || true

# Run the DB container, keeping stdout clean for command substitution.
# --ip is added only when EXTERNAL_DB_FIXED_IP is set (used by the swap
# path to keep the same address across the PG14 -> PG16 replacement).
container_id="$(docker run -d \
  --name "${POSTGRES_CONTAINER_NAME}" \
  --network kind \
  ${EXTERNAL_DB_FIXED_IP:+--ip "${EXTERNAL_DB_FIXED_IP}"} \
  ${POSTGRES_DATA_VOLUME:+-v "${POSTGRES_DATA_VOLUME}":/var/lib/postgresql/data} \
  -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  -e POSTGRES_DB=postgres \
  -e POSTGRES_USER=${POSTGRES_USER} \
  -v "${SSL_VOLUME}:/ssl:ro" \
  "postgres:${POSTGRES_VERSION}" \
  -c ssl=on \
  -c ssl_cert_file=/ssl/server.crt \
  -c ssl_key_file=/ssl/server.key \
  -c listen_addresses='*')"

if [[ -n "${container_id}" ]]; then
  echo "Started postgres ${POSTGRES_VERSION} container ${container_id}" >&2
fi

# Wait until ready
for attempt_number in $(seq 1 60); do
  if docker exec "${POSTGRES_CONTAINER_NAME}" pg_isready -U ${POSTGRES_USER} >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

EXTERNAL_DB_HOST="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${POSTGRES_CONTAINER_NAME}" | tr -d '\n')"

if [[ -z "${EXTERNAL_DB_HOST}" ]]; then
  echo "Failed to determine external postgres IP" >&2
  exit 1
fi

if ! [[ "${EXTERNAL_DB_HOST}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid external postgres IP: ${EXTERNAL_DB_HOST}" >&2
  exit 1
fi

echo "${EXTERNAL_DB_HOST}"
