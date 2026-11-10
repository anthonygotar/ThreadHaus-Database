#!/bin/bash
# Loads the ThreadHaus schema and sample data into the replication primary
# through the published port 127.0.0.1:5440. The password is read from .env
# in this folder and passed to psql through the PGPASSWORD environment
# variable, so it is never printed or written to a file.

set -e
cd "$(dirname "$0")"

if [ ! -f .env ]; then
    echo "error: .env not found in $(pwd)" >&2
    exit 1
fi

POSTGRES_PASSWORD="$(grep -E '^POSTGRES_PASSWORD=' .env | head -1 | cut -d= -f2-)"
if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "error: POSTGRES_PASSWORD is missing in .env" >&2
    exit 1
fi

SCHEMA=../../portfolio-1-database-design/schema.sql
DATA=../../portfolio-1-database-design/sample-data.sql

PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -p 5440 -U postgres -d threadhaus \
    -v ON_ERROR_STOP=1 -f "$SCHEMA"
PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -p 5440 -U postgres -d threadhaus \
    -v ON_ERROR_STOP=1 -f "$DATA"

echo "load-threadhaus: schema and sample data loaded into the primary via 127.0.0.1:5440"
