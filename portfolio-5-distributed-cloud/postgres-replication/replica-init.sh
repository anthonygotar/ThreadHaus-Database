#!/bin/bash
# Entrypoint for the ThreadHaus replica container. On first boot the data
# directory is empty, so I take a base backup from the primary with
# pg_basebackup -R, which writes standby.signal and primary_conninfo, and
# a physical replication slot. The WAL receiver then authenticates with a
# .pgpass file (pg_basebackup -R never writes the password into
# primary_conninfo). After that I hand over to the standard postgres image
# entrypoint, which starts the server in hot standby mode.

set -e

: "${PGDATA:=/var/lib/postgresql/18/docker}"
: "${PRIMARY_HOST:=pg-primary}"
: "${REPLICATION_SLOT:=threadhaus_replica}"
: "${REPLICATOR_PASSWORD:?REPLICATOR_PASSWORD must be set}"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "replica-init: data directory empty, taking base backup from $PRIMARY_HOST"

    mkdir -p "$PGDATA"
    chown postgres:postgres "$(dirname "$PGDATA")" "$PGDATA"
    chmod 700 "$PGDATA"

    # The primary's init phase runs a socket-only temp server, so TCP
    # pg_isready only succeeds once the real server, with the replication
    # role and pg_hba rules in place, is up.
    until pg_isready -h "$PRIMARY_HOST" -p 5432 -U replicator -d postgres -q; do
        echo "replica-init: waiting for $PRIMARY_HOST to accept connections"
        sleep 1
    done

    cat > /var/lib/postgresql/.pgpass <<EOF
$PRIMARY_HOST:5432:*:replicator:$REPLICATOR_PASSWORD
EOF
    chown postgres:postgres /var/lib/postgresql/.pgpass
    chmod 600 /var/lib/postgresql/.pgpass

    # pg_basebackup authenticates through the .pgpass file above
    # (PGPASSFILE is set in docker-compose.yml). I deliberately avoid
    # PGPASSWORD here: pg_basebackup -R copies the connection parameters
    # into primary_conninfo, and a password supplied through PGPASSWORD
    # would end up written into postgresql.auto.conf.
    gosu postgres pg_basebackup \
        -d "host=$PRIMARY_HOST port=5432 user=replicator application_name=threadhaus_replica" \
        -D "$PGDATA" \
        --slot="$REPLICATION_SLOT" --create-slot \
        -R -X stream -c fast -P

    # Safety net: strip any password token from primary_conninfo.
    sed -i "s/ password=[^ ]*//" "$PGDATA/postgresql.auto.conf"

    chown -R postgres:postgres "$PGDATA"
    chmod 700 "$PGDATA"
    echo "replica-init: base backup complete, starting as standby"
fi

exec docker-entrypoint.sh "$@"
