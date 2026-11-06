#!/usr/bin/env bash
# reset-db.sh
# Drops and recreates the threadhaus database, loads the schema and sample data.
# Run from the portfolio-3-transactions-concurrency/ directory.
# Uses plain psql with PGHOST, PGUSER set in the environment.
# Every transaction scenario starts by running this script so results are repeatable.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORTFOLIO1="$SCRIPT_DIR/../portfolio-1-database-design"

echo "Dropping and recreating threadhaus..."
psql -d postgres -c "DROP DATABASE IF EXISTS threadhaus;"
psql -d postgres -c "CREATE DATABASE threadhaus;"

echo "Loading schema..."
psql -v ON_ERROR_STOP=1 -d threadhaus -f "$PORTFOLIO1/schema.sql"

echo "Loading sample data..."
psql -v ON_ERROR_STOP=1 -d threadhaus -f "$PORTFOLIO1/sample-data.sql"

echo "reset done"
