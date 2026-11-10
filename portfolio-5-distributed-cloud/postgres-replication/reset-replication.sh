#!/bin/bash
# Tears down the portfolio 5 replication stack and brings it back from
# scratch: docker compose down -v removes the primary and replica data
# volumes, so the next up re-runs the container init scripts (replication
# role, slot, pg_hba rules, base backup). Then the portfolio 1 schema and
# sample data are loaded into the primary via load-threadhaus.sh, and the
# script waits until the replica is streaming again and has caught up.
# Only the threadhaus-pg-replication project (this folder) is touched.

set -u
cd "$(dirname "$0")"

ts() { date -u '+%Y-%m-%d %H:%M:%S.%3NZ'; }

TOTAL_QUERY="SELECT (SELECT count(*) FROM customer)
    + (SELECT count(*) FROM address)
    + (SELECT count(*) FROM category)
    + (SELECT count(*) FROM product)
    + (SELECT count(*) FROM product_variant)
    + (SELECT count(*) FROM orders)
    + (SELECT count(*) FROM order_item)
    + (SELECT count(*) FROM payment)
    + (SELECT count(*) FROM rider)
    + (SELECT count(*) FROM delivery)
    + (SELECT count(*) FROM return_request)
    + (SELECT count(*) FROM complaint)
    + (SELECT count(*) FROM review)
    + (SELECT count(*) FROM staff);"

echo "reset-replication: started $(ts)"
echo "-- docker compose down -v (stops the stack, removes its volumes and network) --"
docker compose down -v
echo "-- docker compose up -d (fresh primary init + fresh replica base backup) --"
docker compose up -d

echo "-- waiting for the primary to accept connections --"
PRIMARY_READY=no
for i in $(seq 1 60); do
    if docker exec threadhaus-pg-primary pg_isready -U postgres -d threadhaus -q >/dev/null 2>&1; then
        echo "primary ready after ~${i}s"
        PRIMARY_READY=yes
        break
    fi
    sleep 1
done
[ "$PRIMARY_READY" = yes ] || { echo "primary never became ready"; exit 1; }

echo "-- waiting for the replica to be streaming from the primary --"
STREAMING=no
for i in $(seq 1 120); do
    STATE=$(docker exec threadhaus-pg-primary psql -U postgres -d postgres -Atc \
      "SELECT state FROM pg_stat_replication WHERE application_name = 'threadhaus_replica';" \
      2>/dev/null || true)
    if [ "$STATE" = "streaming" ]; then
        echo "replica streaming after ~${i}s"
        STREAMING=yes
        break
    fi
    sleep 1
done
[ "$STREAMING" = yes ] || { echo "replica never reached streaming state"; exit 1; }

echo "-- loading portfolio 1 schema and sample data into the primary --"
bash load-threadhaus.sh

echo "-- waiting until the replica has replayed the loaded data --"
for i in $(seq 1 60); do
    P=$(docker exec threadhaus-pg-primary psql -U postgres -d threadhaus -Atc "$TOTAL_QUERY" 2>/dev/null || true)
    R=$(docker exec threadhaus-pg-replica psql -U postgres -d threadhaus -Atc "$TOTAL_QUERY" 2>/dev/null || true)
    if [ -n "$P" ] && [ "$P" = "$R" ]; then
        echo "replica caught up after ~${i}s: $R rows across the 14 ThreadHaus tables on both sides"
        break
    fi
    sleep 1
done

echo "-- final replication status --"
docker exec threadhaus-pg-primary psql -U postgres -d postgres -c \
  "SELECT application_name, client_addr, state, sync_state, sent_lsn, replay_lsn FROM pg_stat_replication;"
docker compose ps
echo "reset-replication: finished $(ts)"
