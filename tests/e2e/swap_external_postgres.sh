#!/usr/bin/env bash
# In-place upgrade of the external postgres container from one major
# version to another via pg_upgrade.  The existing data volume's
# contents are migrated to a new volume in the target format, then a
# new postgres container is started on the same network, IP, and SSL
# settings — chart-deployed pods see no hostname change and the
# database keeps its data.
#
# Used by test_db_upgrade_standalone_db to mirror what real customers
# do on managed Postgres (RDS / CloudSQL / GCP) where the major version
# bump preserves data.  Because data carries over, the chart's
# db-upgrade job sees an existing DB (settings table present) and
# SKIPS pg_restore — exercising the "Database exists, running upgrade
# now..." branch in templates/db-upgrade-job.yaml.
#
# Implementation note: tianon/postgres-upgrade:<old>-to-<new> is a
# community image carrying both postgres binaries; its entrypoint runs
# initdb on the destination then pg_upgrade between the two volumes.
set -euo pipefail

NEW_VERSION="${1:?usage: swap_external_postgres.sh <postgres-major-version>}"
POSTGRES_CONTAINER_NAME="${POSTGRES_CONTAINER_NAME:-kasm-e2e-postgres}"
POSTGRES_USER="${POSTGRES_USER:-kasmapp}"

# --- Discover state of the running container --------------------------------

current_ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${POSTGRES_CONTAINER_NAME}" 2>/dev/null | tr -d '\n' || true)"
if [[ -z "${current_ip}" ]]; then
  echo "swap_external_postgres.sh: container '${POSTGRES_CONTAINER_NAME}' is not running" >&2
  exit 1
fi

old_image="$(docker inspect -f '{{.Config.Image}}' "${POSTGRES_CONTAINER_NAME}")"
OLD_VERSION="${old_image##*:}"

# Old data volume must be a *named* volume mounted at the postgres data
# directory, otherwise pg_upgrade has nothing to read after we remove
# the container.
OLD_DATA_VOLUME="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}' "${POSTGRES_CONTAINER_NAME}")"
if [[ -z "${OLD_DATA_VOLUME}" ]]; then
  echo "swap_external_postgres.sh: ${POSTGRES_CONTAINER_NAME} was started without a named data volume." >&2
  echo "Re-start it with POSTGRES_DATA_VOLUME=<name> set so the data survives the swap." >&2
  exit 1
fi

NEW_DATA_VOLUME="kasm-e2e-postgres-data-${NEW_VERSION}"

# --- Stop the old container --------------------------------------------------
docker stop "${POSTGRES_CONTAINER_NAME}" >/dev/null
docker rm   "${POSTGRES_CONTAINER_NAME}" >/dev/null

# --- pg_upgrade: old volume -> new volume ------------------------------------
# Always recreate the destination volume so initdb starts on an empty dir.
docker volume rm     "${NEW_DATA_VOLUME}" >/dev/null 2>&1 || true
docker volume create "${NEW_DATA_VOLUME}" >/dev/null

UPGRADE_IMAGE="tianon/postgres-upgrade:${OLD_VERSION}-to-${NEW_VERSION}"
echo "Running pg_upgrade ${OLD_VERSION} -> ${NEW_VERSION} via ${UPGRADE_IMAGE}" >&2

docker run --rm \
  -v "${OLD_DATA_VOLUME}:/var/lib/postgresql/${OLD_VERSION}/data" \
  -v "${NEW_DATA_VOLUME}:/var/lib/postgresql/${NEW_VERSION}/data" \
  -e PGUSER="${POSTGRES_USER}" \
  -e POSTGRES_INITDB_ARGS="-U ${POSTGRES_USER}" \
  --user "999:999" \
  "${UPGRADE_IMAGE}"

# pg_upgrade does not copy pg_hba.conf from the old cluster, and the
# postgres image entrypoint only writes the "host all all all <method>"
# rule during the initial initdb path — which it skips because our new
# data dir is now populated.  Without this rule the new server only
# accepts local connections, leaving the chart's init container hanging
# on "DB is not reachable or queryable".  Append the rule once.
echo "Patching pg_hba.conf in upgraded data volume to allow external connections" >&2
docker run --rm \
  -v "${NEW_DATA_VOLUME}:/var/lib/postgresql/data" \
  --user "999:999" \
  --entrypoint /bin/bash \
  "postgres:${NEW_VERSION}" \
  -c 'HBA=/var/lib/postgresql/data/pg_hba.conf; grep -q "^host all all all" "$HBA" || echo "host all all all scram-sha-256" >> "$HBA"'

# --- Start the new postgres container, same IP, new data volume --------------
export POSTGRES_VERSION="${NEW_VERSION}"
export POSTGRES_DATA_VOLUME="${NEW_DATA_VOLUME}"
export EXTERNAL_DB_FIXED_IP="${current_ip}"
exec "$(dirname "$0")/start_external_postgres.sh"
