#!/bin/bash
# Runs once inside the pg-primary container on first boot (empty data
# directory), during the postgres image init phase. It creates the
# replication role the replica logs in with and replaces the image's
# blanket "host all all all" TCP rule with rules scoped to this compose
# network. The password comes from the REPLICATOR_PASSWORD environment
# variable, so it is never printed or committed.

set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '${REPLICATOR_PASSWORD}';
EOSQL

sed -i '/^host all all all /d' "$PGDATA/pg_hba.conf"

cat >> "$PGDATA/pg_hba.conf" <<EOF

# ThreadHaus replication rules, added by 10-replication-setup.sh
# The replica streams WAL from inside the compose network only.
host replication replicator ${REPLICATION_NETWORK_CIDR} scram-sha-256
host postgres replicator ${REPLICATION_NETWORK_CIDR} scram-sha-256
# Connections from the host through the published port arrive from the
# Docker network gateway address.
host threadhaus,postgres postgres ${REPLICATION_HOST_GATEWAY}/32 scram-sha-256
EOF

echo "10-replication-setup: replication role and pg_hba rules in place"
