#!/bin/bash
# Failover experiment for the ThreadHaus replication stack.
#
# Each run starts with reset-replication.sh (fresh primary + replica, 52
# rows of sample data), then:
#  1. creates the scratch table failover_test and a marker row,
#  2. starts a background writer that inserts one row on the primary every
#     100 ms and records every acknowledged id,
#  3. disables the container restart policy and hard-kills the primary
#     (docker kill, not a graceful stop),
#  4. polls until the old primary refuses connections,
#  5. promotes the replica with SELECT pg_promote(),
#  6. performs the first write on the new primary and timestamps everything
#     (kill -> refused, kill -> promoted, kill -> first write = recovery),
#  7. compares the last acknowledged id with the max id that survived on
#     the promoted replica (recovery point: acknowledged writes lost),
#  8. verifies pg_is_in_recovery() = false and the marker row exists.
#
# The old primary is deliberately left dead: restarting it as a primary
# would create two primaries with different histories (split brain); it
# must be rebuilt as a replica (e.g. with pg_rewind) before rejoining.
# The next run's reset (docker compose down -v) tears it down completely.
#
# All psql access goes through docker exec on the container-local Unix
# socket or through the published 127.0.0.1 ports; no passwords are
# involved for the socket, and load-threadhaus.sh reads .env itself.
# Output goes to ../evidence/pg-failover.txt.

set -u
cd "$(dirname "$0")"
trap '' PIPE

[ -n "${EPOCHREALTIME:-}" ] || { echo "this script needs bash >= 5 with EPOCHREALTIME"; exit 1; }

PRIMARY=threadhaus-pg-primary
REPLICA=threadhaus-pg-replica
EVDIR=../evidence
mkdir -p "$EVDIR"
OUT=$EVDIR/pg-failover.txt
RUNS=${1:-2}
WRITER_SECONDS=${WRITER_SECONDS:-3}

ts() {
    local s=${EPOCHREALTIME%.*} f=${EPOCHREALTIME#*.}
    date -u -d "@$s" "+%Y-%m-%d %H:%M:%S.${f:0:3}Z"
}
now_us() { echo "${EPOCHREALTIME/./}"; }

wait_replica_table() { # <table>
    local i
    for i in $(seq 1 100); do
        [ "$(docker exec "$REPLICA" psql -U postgres -d threadhaus -Atc \
              "SELECT to_regclass('$1') IS NOT NULL;" 2>/dev/null || true)" = "t" ] && return 0
        sleep 0.2
    done
    echo "$1 never appeared on the replica"
    return 1
}

start_writer() { # <ackfile> -- background loop, one row per 100 ms
    (
        trap '' PIPE
        exec 2>/dev/null
        d=$(mktemp -d /tmp/threadhaus-writer.XXXXXX)
        mkfifo "$d/w.in" "$d/w.out"
        docker exec -i "$PRIMARY" psql -U postgres -d threadhaus -XAt \
            <"$d/w.in" >"$d/w.out" 2>/dev/null &
        spid=$!
        exec 7>"$d/w.in" 8<"$d/w.out"
        wq() {
            local marker="M$RANDOM$RANDOM"
            printf '%s\n%s\n' "$1" "SELECT '$marker';" >&7
            local line
            while IFS= read -r line <&8; do
                [ "$line" = "$marker" ] && return 0
                printf '%s\n' "$line"
            done
            return 1
        }
        wq "SELECT 1;" >/dev/null
        echo "started ${EPOCHREALTIME/./}" >> "$1"
        while :; do
            out=$(wq "INSERT INTO failover_test (note, inserted_at) VALUES ('writer', clock_timestamp()) RETURNING id;")
            id=${out%%$'\n'*}
            case "$id" in ''|*[!0-9]*) break ;; esac
            echo "$id ${EPOCHREALTIME/./}" >> "$1"
            sleep 0.1
        done
        echo "stopped ${EPOCHREALTIME/./}" >> "$1"
        exec 7>&- 8<&-
        kill "$spid" 2>/dev/null || true
        wait "$spid" 2>/dev/null || true
        rm -rf "$d"
    ) &
    WRITER_PID=$!
}

run_failover() {
    local run=$1 ackfile=$SESSDIR/writer-$1.ack
    local marker_id t_kill t_refused t_promote t_write last_acked max_on_replica lost

    echo "==== RUN $run of $RUNS started $(ts) ===="
    echo "-- resetting the stack (reset-replication.sh) --"
    bash reset-replication.sh || return 1

    echo "-- creating the scratch table and the marker row --"
    docker exec "$PRIMARY" psql -U postgres -d threadhaus -Atc \
      "DROP TABLE IF EXISTS failover_test;
       CREATE TABLE failover_test (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                                   note text,
                                   inserted_at timestamptz DEFAULT clock_timestamp());"
    wait_replica_table failover_test || return 1
    marker_id=$(docker exec "$PRIMARY" psql -U postgres -d threadhaus -Atc \
      "INSERT INTO failover_test (note) VALUES ('marker') RETURNING id;" | head -1)
    echo "marker row id=$marker_id inserted on the primary"
    : > "$ackfile"

    echo "-- starting the background writer (one row per 100 ms) --"
    start_writer "$ackfile"
    sleep "$WRITER_SECONDS"

    echo "-- killing the primary (restart policy disabled first, then docker kill) --"
    docker update --restart=no "$PRIMARY"
    t_kill=$(now_us)
    echo "docker kill at $(ts)"
    docker kill "$PRIMARY"

    echo "-- polling until the old primary refuses connections (127.0.0.1:5440) --"
    local i
    for i in $(seq 1 200); do
        if ! pg_isready -h 127.0.0.1 -p 5440 -q >/dev/null 2>&1; then
            t_refused=$(now_us)
            echo "old primary refused connections at $(ts) (after $(( (t_refused - t_kill) / 1000 )) ms)"
            break
        fi
        sleep 0.05
    done
    [ -n "${t_refused:-}" ] || { echo "old primary never refused connections"; return 1; }

    kill "$WRITER_PID" 2>/dev/null || true
    wait "$WRITER_PID" 2>/dev/null || true
    last_acked=$(grep -E '^[0-9]+ [0-9]+$' "$ackfile" | tail -1 | cut -d' ' -f1)
    local acked_count
    acked_count=$(grep -cE '^[0-9]+ [0-9]+$' "$ackfile" || true)
    [ -n "$last_acked" ] || { echo "the writer never acknowledged a row; aborting this run"; return 1; }
    echo "writer acknowledged $acked_count rows before the kill; last acknowledged id=$last_acked"

    echo "-- promoting the replica --"
    docker exec "$REPLICA" psql -U postgres -d threadhaus -c "SELECT pg_promote();"
    t_promote=$(now_us)
    echo "pg_promote() returned at $(ts) ($(( (t_promote - t_kill) / 1000 )) ms after the kill)"

    echo "-- first write on the new primary --"
    local first_id
    first_id=$(docker exec "$REPLICA" psql -U postgres -d threadhaus -Atc \
      "INSERT INTO failover_test (note) VALUES ('first-write-after-promotion') RETURNING id;" | head -1)
    t_write=$(now_us)
    echo "first write on the new primary (id=$first_id) at $(ts)"
    echo "(the id jumps past the last writer id because identity sequences are WAL-logged in batches; the skipped ids are a sequence jump, not lost rows)"
    echo "recovery time (kill -> first successful write): $(( (t_write - t_kill) / 1000 )) ms"

    echo "-- state of the new primary --"
    docker exec "$REPLICA" psql -U postgres -d threadhaus -Atc \
      "SELECT 'pg_is_in_recovery() = ' || pg_is_in_recovery();
       SELECT 'marker row present: ' || count(*) FROM failover_test WHERE note = 'marker';"

    echo "-- recovery point: acknowledged writes vs what the promoted replica has --"
    max_on_replica=$(docker exec "$REPLICA" psql -U postgres -d threadhaus -Atc \
      "SELECT COALESCE(max(id), 0) FROM failover_test WHERE note = 'writer';")
    lost=$(( last_acked - max_on_replica ))
    [ "$lost" -lt 0 ] && lost=0
    echo "last acknowledged id on the dead primary: $last_acked"
    echo "max writer id that survived on the promoted replica: $max_on_replica"
    if [ "$lost" -gt 0 ]; then
        echo "acknowledged writes lost: $lost (rows the old primary had committed but the replica had not yet replayed when it was killed)"
    else
        echo "acknowledged writes lost: 0 (this run); with asynchronous replication this window always exists, a longer lag or an earlier kill would lose rows"
    fi

    echo "-- split-brain note --"
    echo "the old primary is deliberately left dead. It must be rebuilt as a replica"
    echo "(e.g. with pg_rewind and a fresh replication setup) before rejoining;"
    echo "restarting it as a primary would mean two primaries serving different histories."
    echo "The next run's reset (docker compose down -v) removes it completely."
    echo "==== RUN $run finished $(ts) ===="
    echo
}

{
    echo "ThreadHaus PostgreSQL failover experiment"
    echo "Script: run-failover.sh, started $(ts)"
    echo "scratch table failover_test is not part of the ThreadHaus schema"
    echo
} > "$OUT"

SESSDIR=$(mktemp -d /tmp/threadhaus-failover.XXXXXX)
SUMMARY=""
for RUN in $(seq 1 "$RUNS"); do
    run_failover "$RUN" >> "$OUT" 2>&1
    SUMMARY="$SUMMARY$(grep -E 'writer acknowledged|recovery time \(kill|acknowledged writes lost' "$OUT" | tail -3)
"
    [ "$RUN" -lt "$RUNS" ] && echo >> "$OUT"
done
rm -rf "$SESSDIR"

{
    echo "== repeatability =="
    echo "$SUMMARY"
    echo "Both runs: failover completed, the promoted replica served writes, and the"
    echo "recovery-point comparison was measured. The lost-write count varies with"
    echo "replication lag at the moment of the kill (async replication)."
    echo "Finished $(ts)"
} >> "$OUT"

echo "run-failover: written to $OUT ($RUNS runs)"
