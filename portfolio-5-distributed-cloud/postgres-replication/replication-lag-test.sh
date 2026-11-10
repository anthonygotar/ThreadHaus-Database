#!/bin/bash
# Replication lag test for the ThreadHaus primary/replica pair. Creates a
# scratch table on the primary (not part of the ThreadHaus schema), inserts
# 200,000 rows into it in one statement while sampling pg_stat_replication
# on the primary roughly every 0.5 seconds, then shows the replica catching
# up and the row counts matching. The scratch table is dropped on the
# primary afterwards so the drop replicates too. Everything is written to
# ../evidence/pg-replication-lag.txt.

set -u
cd "$(dirname "$0")"

PRIMARY=threadhaus-pg-primary
REPLICA=threadhaus-pg-replica
OUT=../evidence/pg-replication-lag.txt

elapsed() {
    awk -v a="$1" -v b="$2" 'BEGIN {printf "%.2f", b - a}'
}

sample_lag() {
    docker exec "$PRIMARY" psql -U postgres -d threadhaus -x -c \
      "SELECT clock_timestamp() AS sampled_at, application_name, state, sent_lsn, replay_lsn, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_behind_bytes, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"
}

{
echo "ThreadHaus PostgreSQL streaming replication - lag under load"
echo "Collected: $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "The scratch table lag_scratch exists only for this test and is not part of the ThreadHaus schema."
echo
echo "== create the scratch table on the primary =="
docker exec "$PRIMARY" psql -U postgres -d threadhaus -c "DROP TABLE IF EXISTS lag_scratch;"
docker exec "$PRIMARY" psql -U postgres -d threadhaus -c "CREATE TABLE lag_scratch (id BIGINT NOT NULL, payload TEXT NOT NULL);"

echo
echo "== baseline: replica state before the load =="
sample_lag

echo
echo "== start a 200,000 row insert on the primary in the background =="
INSERT_START=$(date +%s.%N)
docker exec "$PRIMARY" psql -U postgres -d threadhaus -c "INSERT INTO lag_scratch SELECT g, repeat('x', 300) FROM generate_series(1, 200000) AS g;" &
INSERT_PID=$!

echo "== sample pg_stat_replication on the primary every 0.5 s while the insert runs =="
while kill -0 $INSERT_PID 2>/dev/null; do
    sample_lag
    sleep 0.5
done
wait $INSERT_PID
INSERT_END=$(date +%s.%N)
echo "insert finished, wall time on the primary: $(elapsed "$INSERT_START" "$INSERT_END") s"

echo
echo "== keep sampling every 0.5 s until the replica has caught up =="
CATCHUP_START=$(date +%s.%N)
for i in $(seq 1 120); do
    BEHIND=$(docker exec "$PRIMARY" psql -U postgres -d postgres -Atc \
      "SELECT coalesce(max(pg_wal_lsn_diff(sent_lsn, replay_lsn))::bigint, 0) FROM pg_stat_replication;")
    REPLICA_COUNT=$(docker exec "$REPLICA" psql -U postgres -d threadhaus -Atc "SELECT count(*) FROM lag_scratch;")
    echo "poll $i: replay_behind_bytes = $BEHIND, replica lag_scratch rows = $REPLICA_COUNT"
    if [ "$BEHIND" = "0" ] && [ "$REPLICA_COUNT" = "200000" ]; then
        break
    fi
    sleep 0.5
done
CATCHUP_END=$(date +%s.%N)
echo
echo "== replica caught up =="
sample_lag
echo "time from insert end to full replay on the replica: $(elapsed "$INSERT_END" "$CATCHUP_END") s"

echo
echo "== final row counts must match =="
echo "primary: $(docker exec "$PRIMARY" psql -U postgres -d threadhaus -Atc 'SELECT count(*) FROM lag_scratch;') rows in lag_scratch"
echo "replica: $(docker exec "$REPLICA" psql -U postgres -d threadhaus -Atc 'SELECT count(*) FROM lag_scratch;') rows in lag_scratch"

echo
echo "== drop the scratch table on the primary so the drop replicates =="
docker exec "$PRIMARY" psql -U postgres -d threadhaus -c "DROP TABLE lag_scratch;"
for i in $(seq 1 60); do
    GONE=$(docker exec "$REPLICA" psql -U postgres -d threadhaus -Atc "SELECT to_regclass('lag_scratch') IS NULL;")
    if [ "$GONE" = "t" ]; then
        echo "replica dropped the table after $i polls"
        break
    fi
    sleep 0.5
done
echo
echo "== to_regclass('lag_scratch') on the replica (empty result means gone) =="
docker exec "$REPLICA" psql -U postgres -d threadhaus -c "SELECT to_regclass('lag_scratch');"
echo "== to_regclass('lag_scratch') on the primary (empty result means gone) =="
docker exec "$PRIMARY" psql -U postgres -d threadhaus -c "SELECT to_regclass('lag_scratch');"
} > "$OUT" 2>&1

echo "replication-lag-test: written to $OUT"
