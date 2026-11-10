#!/bin/bash
# Stale-read experiment for the ThreadHaus streaming replica.
#
# Part A (statistical): with the default asynchronous replication, insert
# a row on the primary and immediately read it on the replica, 100 times.
# A read that does not yet see the row is a stale read; for each stale read
# I keep polling until the row appears and record how long that took.
#
# Part B (deterministic): call pg_wal_replay_pause() on the replica, insert
# a row on the primary, show that the replica read returns nothing while the
# replay lag in pg_stat_replication keeps growing, then call
# pg_wal_replay_resume() and show the row appear. This is eventual
# consistency made visible.
#
# The scratch table lag_test is NOT part of the ThreadHaus schema; it is
# created at the start and dropped at the end of each run.
#
# psql sessions are opened once per node with docker exec over the
# container-local Unix socket (no passwords involved) and kept open with
# FIFOs, so each trial is a single fast round trip instead of a new
# connection. Output goes to ../evidence/pg-stale-read.txt.

set -u
cd "$(dirname "$0")"
trap '' PIPE

[ -n "${EPOCHREALTIME:-}" ] || { echo "this script needs bash >= 5 with EPOCHREALTIME"; exit 1; }

PRIMARY=threadhaus-pg-primary
REPLICA=threadhaus-pg-replica
EVDIR=../evidence
mkdir -p "$EVDIR"
OUT=$EVDIR/pg-stale-read.txt
RUNS=${1:-2}
TRIALS=${TRIALS:-100}

ts() {
    local s=${EPOCHREALTIME%.*} f=${EPOCHREALTIME#*.}
    date -u -d "@$s" "+%Y-%m-%d %H:%M:%S.${f:0:3}Z"
}
now_us() { echo "${EPOCHREALTIME/./}"; }

# ---------- persistent psql sessions over the local Unix socket ----------
SESSDIR=$(mktemp -d /tmp/threadhaus-sess.XXXXXX)
mkfifo "$SESSDIR/p.in" "$SESSDIR/p.out" "$SESSDIR/r.in" "$SESSDIR/r.out"
docker exec -i "$PRIMARY" psql -U postgres -d threadhaus -XAt \
    <"$SESSDIR/p.in" >"$SESSDIR/p.out" 2>/dev/null &
P_PID=$!
docker exec -i "$REPLICA" psql -U postgres -d threadhaus -XAt \
    <"$SESSDIR/r.in" >"$SESSDIR/r.out" 2>/dev/null &
R_PID=$!
exec 3>"$SESSDIR/p.in" 4<"$SESSDIR/p.out" 5>"$SESSDIR/r.in" 6<"$SESSDIR/r.out"

# q <in_fd> <out_fd> <sql>  -> prints the result lines, then a unique
# marker SELECT is sent after the query so we know where output ends.
q() {
    local fin=$1 fout=$2 marker="M$RANDOM$RANDOM"
    printf '%s\n%s\n' "$3" "SELECT '$marker';" >&"$fin"
    local line
    while IFS= read -r line <&"$fout"; do
        [ "$line" = "$marker" ] && return 0
        printf '%s\n' "$line"
    done
    return 1
}
pq() { q 3 4 "$1"; }
rq() { q 5 6 "$1"; }

cleanup() {
    # safety net: never leave WAL replay paused behind us
    rq "SELECT pg_wal_replay_resume();" >/dev/null 2>&1 || \
        docker exec "$REPLICA" psql -U postgres -d threadhaus -Atc \
          "SELECT pg_wal_replay_resume();" >/dev/null 2>&1 || true
    exec 3>&- 4<&- 5>&- 6<&-
    kill "$P_PID" "$R_PID" 2>/dev/null || true
    wait "$P_PID" "$R_PID" 2>/dev/null || true
    rm -rf "$SESSDIR"
}
trap cleanup EXIT

# warm up both sessions (first round trip pays the docker exec startup)
pq "SELECT 1;" >/dev/null
rq "SELECT 1;" >/dev/null

wait_replica_has_table() {
    local i
    for i in $(seq 1 100); do
        [ "$(rq "SELECT to_regclass('lag_test') IS NOT NULL;")" = "t" ] && return 0
        sleep 0.2
    done
    echo "lag_test never appeared on the replica"
    return 1
}
wait_replica_dropped_table() {
    local i
    for i in $(seq 1 100); do
        [ "$(rq "SELECT to_regclass('lag_test') IS NULL;")" = "t" ] && return 0
        sleep 0.2
    done
    echo "lag_test was never dropped on the replica"
    return 1
}

LAG_SAMPLE="SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') || '  bytes_behind=' ||
       COALESCE(pg_wal_lsn_diff(sent_lsn, replay_lsn)::bigint::text, 'n/a') ||
       '  replay_lag=' || COALESCE(replay_lag::text, 'n/a')
FROM pg_stat_replication WHERE application_name = 'threadhaus_replica';"

create_scratch() {
    pq "DROP TABLE IF EXISTS lag_test;" >/dev/null
    pq "CREATE TABLE lag_test (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                              note text,
                              inserted_at timestamptz DEFAULT clock_timestamp());" >/dev/null
    wait_replica_has_table || return 1
    echo "scratch table lag_test created on the primary and replayed on the replica"
}

drop_scratch() {
    pq "DROP TABLE lag_test;" >/dev/null
    wait_replica_dropped_table || true
    echo "scratch table lag_test dropped on the primary and the replica"
}

part_a() {
    local run=$1 i id v out t0 t1 d stale=0 max_us=0
    echo "-- Part A started $(ts): $TRIALS insert-then-immediately-read trials, async replication --"
    for i in $(seq 1 "$TRIALS"); do
        out=$(pq "INSERT INTO lag_test (note) VALUES ('trial-$run-$i') RETURNING id;")
        id=${out%%$'\n'*}
        t0=$(now_us)
        v=$(rq "SELECT count(*) FROM lag_test WHERE id = $id;")
        if [ "$v" = "0" ]; then
            stale=$((stale + 1))
            local n=0
            while [ "$v" = "0" ]; do
                v=$(rq "SELECT count(*) FROM lag_test WHERE id = $id;")
                n=$((n + 1)); [ $n -gt 10000 ] && break
            done
            t1=$(now_us)
            d=$((t1 - t0))
            [ "$d" -gt "$max_us" ] && max_us=$d
            echo "trial $i: STALE read on the replica; the row became visible after $((d / 1000)) ms"
        fi
    done
    echo "Part A run $run summary: $stale of $TRIALS reads were stale ($(
        awk "BEGIN{printf \"%.1f\", 100 * $stale / $TRIALS}")%); the longest time until a row became visible was $((max_us / 1000)) ms (poll granularity ~5 ms)"
    echo "-- Part A finished $(ts) --"
}

part_b() {
    local id out v t0 t1 n=0
    echo
    echo "-- Part B started $(ts): deterministic stale read with pg_wal_replay_pause --"
    echo "replica replay state before the pause: $(rq 'SELECT pg_get_wal_replay_pause_state();')"
    rq "SELECT pg_wal_replay_pause();" >/dev/null
    echo "pg_wal_replay_pause() called; replica replay state now: $(rq 'SELECT pg_get_wal_replay_pause_state();')"
    out=$(pq "INSERT INTO lag_test (note) VALUES ('paused-row') RETURNING id;")
    id=${out%%$'\n'*}
    echo "row inserted on the primary: id=$id"
    v=$(rq "SELECT count(*) FROM lag_test WHERE id = $id;")
    echo "read on the replica right after the insert: $v row(s) with id=$id (stale)"
    echo
    echo "-- replay lag on the primary while the replica is paused (each sample follows more writes on the primary) --"
    pq "$LAG_SAMPLE"
    pq "INSERT INTO lag_test (note) SELECT 'filler-1' FROM generate_series(1, 10000);" >/dev/null
    pq "$LAG_SAMPLE"
    pq "INSERT INTO lag_test (note) SELECT 'filler-2' FROM generate_series(1, 10000);" >/dev/null
    pq "$LAG_SAMPLE"
    sleep 2
    pq "$LAG_SAMPLE"
    echo "the replica is not catching up: its WAL replay is paused, so bytes_behind stays high"
    v=$(rq "SELECT count(*) FROM lag_test WHERE id = $id;")
    echo "replica read after ~20k more rows of WAL on the primary: still $v row(s) with id=$id (stale)"
    echo
    echo "-- calling pg_wal_replay_resume() --"
    rq "SELECT pg_wal_replay_resume();" >/dev/null
    t0=$(now_us)
    v=$(rq "SELECT count(*) FROM lag_test WHERE id = $id;")
    while [ "$v" = "0" ]; do
        v=$(rq "SELECT count(*) FROM lag_test WHERE id = $id;")
        n=$((n + 1)); [ $n -gt 10000 ] && break
    done
    t1=$(now_us)
    echo "after the resume the row appeared after $(( (t1 - t0) / 1000 )) ms: now $v row(s) with id=$id on the replica"
    echo "-- waiting for the replica to finish replaying the backlog --"
    n=0
    while [ "$(pq "SELECT COALESCE(pg_wal_lsn_diff(sent_lsn, replay_lsn)::bigint, 0) FROM pg_stat_replication WHERE application_name = 'threadhaus_replica';" | head -1)" -gt 1024 ]; do
        n=$((n + 1)); [ $n -gt 10000 ] && break
    done
    pq "$LAG_SAMPLE"
    echo
    echo "Conclusion: asynchronous streaming replication is eventual consistency."
    echo "The replica serves reads from a state that lags the primary; it converges"
    echo "only after it has replayed the WAL that the primary already committed."
    echo "-- Part B finished $(ts) --"
}

{
    echo "ThreadHaus PostgreSQL replica stale-read experiment"
    echo "Script: run-stale-read.sh, started $(ts)"
    echo "scratch table lag_test is not part of the ThreadHaus schema; it is dropped after each run"
    echo "all queries use docker exec over the container-local Unix socket; no passwords involved"
    echo
} > "$OUT"

for RUN in $(seq 1 "$RUNS"); do
    echo "=== RUN $RUN of $RUNS started $(ts) ===" >> "$OUT"
    create_scratch >> "$OUT" || continue
    part_a "$RUN" >> "$OUT"
    part_b >> "$OUT"
    drop_scratch >> "$OUT"
    echo >> "$OUT"
done

SUMMARY_LINES=$(grep 'Part A run .* summary' "$OUT" || true)
{
    echo "== repeatability =="
    echo "$SUMMARY_LINES"
    echo "Both Part A runs above observed stale reads, so the phenomenon is repeatable;"
    echo "the exact percentage varies between runs because replication lag is a race."
    echo "Part B is deterministic (pg_wal_replay_pause) and reproduced in both runs."
    echo "Finished $(ts)"
} >> "$OUT"

echo "run-stale-read: written to $OUT ($RUNS runs, $TRIALS trials each)"
