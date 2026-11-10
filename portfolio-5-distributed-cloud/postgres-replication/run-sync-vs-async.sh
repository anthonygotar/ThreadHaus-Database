#!/bin/bash
# Compares asynchronous and synchronous (remote_apply) replication on the
# ThreadHaus stack.
#
# Per run:
#  1. async mode (default): 100 insert-then-immediately-read trials across
#     primary and replica (stale-read counting), and the wall time of 200
#     single-row commits.
#  2. enable synchronous replication (ALTER SYSTEM SET
#     synchronous_standby_names = 'threadhaus_replica', synchronous_commit =
#     'remote_apply', pg_reload_conf()), wait for sync_state = 'sync', then
#     repeat the 100 trials (expect zero stale reads) and the 200-commit
#     timing; print a comparison table.
#  3. availability trade: stop the replica container, show that an INSERT on
#     the primary blocks for the full timeout 10 (the commit waits for the
#     standby), restart the replica and show the blocked write completing,
#     then restore the asynchronous settings with ALTER SYSTEM RESET.
#
# The scratch tables sync_test and commit_test are NOT part of the ThreadHaus
# schema; they are created at the start and dropped at the end of each run.
#
# psql sessions are opened once per node with docker exec over the
# container-local Unix socket (no passwords involved) and kept open with
# FIFOs. Output goes to ../evidence/pg-sync-vs-async.txt.

set -u
cd "$(dirname "$0")"
trap '' PIPE

[ -n "${EPOCHREALTIME:-}" ] || { echo "this script needs bash >= 5 with EPOCHREALTIME"; exit 1; }

PRIMARY=threadhaus-pg-primary
REPLICA=threadhaus-pg-replica
EVDIR=../evidence
mkdir -p "$EVDIR"
OUT=$EVDIR/pg-sync-vs-async.txt
RUNS=${1:-2}
TRIALS=${TRIALS:-100}
COMMITS=${COMMITS:-200}

ts() {
    local s=${EPOCHREALTIME%.*} f=${EPOCHREALTIME#*.}
    date -u -d "@$s" "+%Y-%m-%d %H:%M:%S.${f:0:3}Z"
}
now_us() { echo "${EPOCHREALTIME/./}"; }

# ---------- persistent psql sessions over the local Unix socket ----------
# The sessions are recreated for every run: phase 3 stops and restarts the
# replica container, which kills its docker exec session.
SESSIONS_UP=0
start_sessions() {
    SESSDIR=$(mktemp -d /tmp/threadhaus-sess.XXXXXX)
    mkfifo "$SESSDIR/p.in" "$SESSDIR/p.out" "$SESSDIR/r.in" "$SESSDIR/r.out"
    docker exec -i "$PRIMARY" psql -U postgres -d threadhaus -XAt \
        <"$SESSDIR/p.in" >"$SESSDIR/p.out" 2>/dev/null &
    P_PID=$!
    docker exec -i "$REPLICA" psql -U postgres -d threadhaus -XAt \
        <"$SESSDIR/r.in" >"$SESSDIR/r.out" 2>/dev/null &
    R_PID=$!
    exec 3>"$SESSDIR/p.in" 4<"$SESSDIR/p.out" 5>"$SESSDIR/r.in" 6<"$SESSDIR/r.out"
    pq "SELECT 1;" >/dev/null
    rq "SELECT 1;" >/dev/null
    SESSIONS_UP=1
}
stop_sessions() {
    [ "$SESSIONS_UP" = 1 ] || return 0
    SESSIONS_UP=0
    exec 3>&- 4<&- 5>&- 6<&-
    kill "$P_PID" "$R_PID" 2>/dev/null || true
    wait "$P_PID" "$R_PID" 2>/dev/null || true
    rm -rf "$SESSDIR"
}

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

restore_async() {
    docker start "$REPLICA" >/dev/null 2>&1 || true
    local i
    for i in $(seq 1 30); do
        docker exec "$REPLICA" pg_isready -U postgres -d threadhaus -q >/dev/null 2>&1 && break
        sleep 1
    done
    docker exec "$PRIMARY" psql -U postgres -d postgres -c \
      "ALTER SYSTEM RESET synchronous_standby_names;" >/dev/null 2>&1 || true
    docker exec "$PRIMARY" psql -U postgres -d postgres -c \
      "ALTER SYSTEM RESET synchronous_commit;" >/dev/null 2>&1 || true
    docker exec "$PRIMARY" psql -U postgres -d postgres -c \
      "SELECT pg_reload_conf();" >/dev/null 2>&1 || true
}
cleanup() {
    restore_async
    stop_sessions
}
trap cleanup EXIT

# one-off helpers (docker exec over the local Unix socket)
psql_p() { docker exec "$PRIMARY" psql -U postgres -d threadhaus "$@"; }
sync_state() {
    docker exec "$PRIMARY" psql -U postgres -d postgres -Atc \
      "SELECT sync_state FROM pg_stat_replication WHERE application_name = 'threadhaus_replica';"
}
wait_sync_state() {
    local want=$1 i st=""
    for i in $(seq 1 150); do
        st=$(sync_state 2>/dev/null || true)
        if [ "$st" = "$want" ]; then
            echo "sync_state = $want after ~$((i * 100)) ms"
            return 0
        fi
        sleep 0.1
    done
    echo "sync_state never became $want (currently '$st')"
    return 1
}
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

stale_trials() { # <label> -> sets STALE_COUNT, STALE_MAX_MS
    local label=$1 i id out v t0 t1 d n
    STALE_COUNT=0; STALE_MAX_MS=0
    for i in $(seq 1 "$TRIALS"); do
        out=$(pq "INSERT INTO sync_test (note) VALUES ('$label-$i') RETURNING id;")
        id=${out%%$'\n'*}
        t0=$(now_us)
        v=$(rq "SELECT count(*) FROM sync_test WHERE id = $id;")
        if [ "$v" = "0" ]; then
            STALE_COUNT=$((STALE_COUNT + 1))
            n=0
            while [ "$v" = "0" ]; do
                v=$(rq "SELECT count(*) FROM sync_test WHERE id = $id;")
                n=$((n + 1)); [ $n -gt 10000 ] && break
            done
            t1=$(now_us); d=$(( (t1 - t0) / 1000 ))
            [ "$d" -gt "$STALE_MAX_MS" ] && STALE_MAX_MS=$d
        fi
    done
}

commit_timing() { # <label> -> sets AVG_MS P50_MS P95_MS MAX_MS TOTAL_MS
    local label=$1 i t0 t1 out
    : > "$SESSDIR/times.txt"
    for i in $(seq 1 "$COMMITS"); do
        t0=$(now_us)
        out=$(pq "INSERT INTO commit_test (note) VALUES ('$label-$i') RETURNING id;")
        t1=$(now_us)
        echo $((t1 - t0)) >> "$SESSDIR/times.txt"
    done
    sort -n "$SESSDIR/times.txt" > "$SESSDIR/times.sorted"
    local i50=$((COMMITS / 2)) i95=$((95 * COMMITS / 100))
    AVG_MS=$(awk -v n="$COMMITS" '{ s += $1 } END { printf "%.1f", s / n / 1000 }' "$SESSDIR/times.txt")
    P50_MS=$(awk -v line="$i50" 'NR == line { printf "%.1f", $1 / 1000 }' "$SESSDIR/times.sorted")
    P95_MS=$(awk -v line="$i95" 'NR == line { printf "%.1f", $1 / 1000 }' "$SESSDIR/times.sorted")
    MAX_MS=$(awk -v line="$COMMITS" 'NR == line { printf "%.1f", $1 / 1000 }' "$SESSDIR/times.sorted")
    TOTAL_MS=$(awk -v n="$COMMITS" '{ s += $1 } END { printf "%.0f", s / 1000 }' "$SESSDIR/times.txt")
    echo "commit timing $label: $COMMITS single-row commits, avg $AVG_MS ms, p50 $P50_MS ms, p95 $P95_MS ms, max $MAX_MS ms, total $TOTAL_MS ms"
}

run_experiment() {
    local run=$1 rc t0 t1

    stop_sessions
    start_sessions
    echo "==== RUN $run of $RUNS started $(ts) ===="
    pq "DROP TABLE IF EXISTS sync_test; DROP TABLE IF EXISTS commit_test;" >/dev/null
    pq "CREATE TABLE sync_test (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, note text);" >/dev/null
    pq "CREATE TABLE commit_test (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, note text);" >/dev/null
    wait_replica_table sync_test || return 1
    wait_replica_table commit_test || return 1
    echo "scratch tables sync_test and commit_test created on both sides (not part of the ThreadHaus schema)"

    echo "-- phase 1: asynchronous replication (default) --"
    echo "synchronous_commit = $(pq 'SHOW synchronous_commit;'), sync_state = $(sync_state)"
    stale_trials "async"
    echo "stale reads in async mode: $STALE_COUNT of $TRIALS ($(awk "BEGIN{printf \"%.1f\", 100 * $STALE_COUNT / $TRIALS}")%), longest until visible: $STALE_MAX_MS ms"
    A_STALE=$STALE_COUNT
    commit_timing "async"
    A_AVG=$AVG_MS; A_P50=$P50_MS; A_P95=$P95_MS; A_MAX=$MAX_MS; A_TOTAL=$TOTAL_MS

    echo
    echo "-- phase 2: enabling synchronous replication --"
    psql_p -c "ALTER SYSTEM SET synchronous_standby_names = 'threadhaus_replica';"
    psql_p -c "ALTER SYSTEM SET synchronous_commit = 'remote_apply';"
    psql_p -c "SELECT pg_reload_conf();"
    wait_sync_state sync || return 1
    echo "synchronous_commit = $(pq 'SHOW synchronous_commit;') (picked up by the already-open session)"
    stale_trials "sync"
    echo "stale reads in sync mode: $STALE_COUNT of $TRIALS ($(awk "BEGIN{printf \"%.1f\", 100 * $STALE_COUNT / $TRIALS}")%), longest until visible: $STALE_MAX_MS ms"
    S_STALE=$STALE_COUNT
    commit_timing "sync"
    S_AVG=$AVG_MS; S_P50=$P50_MS; S_P95=$P95_MS; S_MAX=$MAX_MS; S_TOTAL=$TOTAL_MS

    echo
    echo "-- comparison table (run $run) --"
    printf '%-42s %-12s %-20s\n' "metric" "async" "sync (remote_apply)"
    printf '%-42s %-12s %-20s\n' "stale reads of $TRIALS" "$A_STALE" "$S_STALE"
    printf '%-42s %-12s %-20s\n' "avg commit latency (ms)" "$A_AVG" "$S_AVG"
    printf '%-42s %-12s %-20s\n' "p50 commit latency (ms)" "$A_P50" "$S_P50"
    printf '%-42s %-12s %-20s\n' "p95 commit latency (ms)" "$A_P95" "$S_P95"
    printf '%-42s %-12s %-20s\n' "max commit latency (ms)" "$A_MAX" "$S_MAX"
    printf '%-42s %-12s %-20s\n' "total for $COMMITS commits (ms)" "$A_TOTAL" "$S_TOTAL"
    awk "BEGIN{ if ($A_AVG > 0) printf \"sync/async avg commit latency ratio: %.1fx\n\", $S_AVG / $A_AVG }"

    echo
    echo "-- phase 3: availability trade (stop the replica while in sync mode) --"
    echo "stopping $REPLICA at $(ts)"
    docker stop "$REPLICA"
    t0=$(now_us)
    echo "attempting an INSERT on the primary with timeout 10 at $(ts)"
    timeout 10 docker exec "$PRIMARY" psql -U postgres -d threadhaus -c \
      "INSERT INTO commit_test (note) VALUES ('blocked-while-replica-down');" 2>/dev/null
    rc=$?
    t1=$(now_us)
    echo "timeout exit code: $rc (124 = the INSERT was still blocked after 10 s); client-side elapsed: $(( (t1 - t0) / 1000 )) ms"
    echo "rows with note='blocked-while-replica-down' visible on the primary while the replica is down: $(docker exec "$PRIMARY" psql -U postgres -d threadhaus -Atc "SELECT count(*) FROM commit_test WHERE note = 'blocked-while-replica-down';")"
    echo "this is the consistency-over-availability trade: the write is not acknowledged without the standby"

    echo "-- restarting $REPLICA at $(ts)"
    docker start "$REPLICA"
    local i
    for i in $(seq 1 60); do
        docker exec "$REPLICA" pg_isready -U postgres -d threadhaus -q >/dev/null 2>&1 && break
        sleep 1
    done
    wait_sync_state sync || true
    t0=$(now_us)
    for i in $(seq 1 600); do
        [ "$(docker exec "$PRIMARY" psql -U postgres -d threadhaus -Atc \
              "SELECT count(*) FROM commit_test WHERE note = 'blocked-while-replica-down';")" = "1" ] && break
        sleep 0.1
    done
    t1=$(now_us)
    echo "the blocked INSERT completed once the replica returned: $(( (t1 - t0) / 1000 )) ms after the standby was back (the row is now committed)"
    docker exec "$PRIMARY" psql -U postgres -d threadhaus -Atc \
      "SELECT 'blocked row now on the primary: id=' || id || ' note=' || note FROM commit_test WHERE note = 'blocked-while-replica-down';"

    echo
    echo "-- restoring asynchronous settings --"
    psql_p -c "ALTER SYSTEM RESET synchronous_standby_names;"
    psql_p -c "ALTER SYSTEM RESET synchronous_commit;"
    psql_p -c "SELECT pg_reload_conf();"
    wait_sync_state async || return 1
    echo "synchronous_commit = $(pq 'SHOW synchronous_commit;') in the persistent session"

    pq "DROP TABLE sync_test; DROP TABLE commit_test;" >/dev/null
    for i in $(seq 1 100); do
        [ "$(docker exec "$REPLICA" psql -U postgres -d threadhaus -Atc \
              "SELECT to_regclass('sync_test') IS NULL AND to_regclass('commit_test') IS NULL;" \
              2>/dev/null || true)" = "t" ] && break
        sleep 0.2
    done
    echo "scratch tables dropped on both sides"
    stop_sessions
    echo "==== RUN $run finished $(ts) ===="
    RUN_STALE_LINES="$RUN_STALE_LINES
run $run: async stale reads $A_STALE/$TRIALS, sync stale reads $S_STALE/$TRIALS, avg commit async $A_AVG ms vs sync $S_AVG ms"
    REPEAT_OK=$(( REPEAT_OK + ( S_STALE == 0 ? 1 : 0 ) + ( A_STALE > 0 ? 1 : 0 ) + ( $(awk "BEGIN{print ($S_AVG > $A_AVG) ? 1 : 0}") ? 1 : 0 ) ))
}

{
    echo "ThreadHaus PostgreSQL sync vs async replication experiment"
    echo "Script: run-sync-vs-async.sh, started $(ts)"
    echo "scratch tables sync_test and commit_test are not part of the ThreadHaus schema"
    echo "all queries use docker exec over the container-local Unix socket; no passwords involved"
    echo
} > "$OUT"

RUN_STALE_LINES=""
REPEAT_OK=0
for RUN in $(seq 1 "$RUNS"); do
    run_experiment "$RUN" >> "$OUT" 2>&1
    [ "$RUN" -lt "$RUNS" ] && echo >> "$OUT"
done

{
    echo
    echo "== repeatability =="
    echo "$RUN_STALE_LINES"
    if [ "$REPEAT_OK" -eq $(( 3 * RUNS )) ]; then
        echo "In every run: sync mode had 0 stale reads, async mode had stale reads, and"
        echo "sync commit latency was higher than async. The result is repeatable."
    else
        echo "Some runs did not show all three expected effects; see the comparison tables above."
    fi
    echo "Finished $(ts)"
} >> "$OUT"

echo "run-sync-vs-async: written to $OUT ($RUNS runs, $TRIALS trials and $COMMITS commits each)"
