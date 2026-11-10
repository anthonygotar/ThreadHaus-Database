#!/bin/bash
# Reprints the portfolio 5 replication proof against the running stack:
# pg_stat_replication and pg_replication_slots on the primary,
# pg_is_in_recovery() on the replica, equal row counts on both sides, a
# new row inserted on the primary and read from the replica, and an INSERT
# on the replica rejected as read-only. All psql calls go through the
# container-local Unix socket (docker exec), so no password is involved.
# Runs the whole check twice so I can say whether it is repeatable.
# Output goes to ../evidence/pg-replication-check.txt.

set -u
cd "$(dirname "$0")"

PRIMARY=threadhaus-pg-primary
REPLICA=threadhaus-pg-replica
EVDIR=../evidence
mkdir -p "$EVDIR"
OUT=$EVDIR/pg-replication-check.txt
RUNS=${1:-2}

ts() { date -u '+%Y-%m-%d %H:%M:%S.%3NZ'; }

COUNTS_QUERY="SELECT 'customer' AS table_name, (SELECT count(*) FROM customer) AS row_count
UNION ALL SELECT 'address', (SELECT count(*) FROM address)
UNION ALL SELECT 'category', (SELECT count(*) FROM category)
UNION ALL SELECT 'product', (SELECT count(*) FROM product)
UNION ALL SELECT 'product_variant', (SELECT count(*) FROM product_variant)
UNION ALL SELECT 'orders', (SELECT count(*) FROM orders)
UNION ALL SELECT 'order_item', (SELECT count(*) FROM order_item)
UNION ALL SELECT 'payment', (SELECT count(*) FROM payment)
UNION ALL SELECT 'rider', (SELECT count(*) FROM rider)
UNION ALL SELECT 'delivery', (SELECT count(*) FROM delivery)
UNION ALL SELECT 'return_request', (SELECT count(*) FROM return_request)
UNION ALL SELECT 'complaint', (SELECT count(*) FROM complaint)
UNION ALL SELECT 'review', (SELECT count(*) FROM review)
UNION ALL SELECT 'staff', (SELECT count(*) FROM staff)
ORDER BY table_name;"

run_once() {
    local run=$1 email="bisi.coker.run$1@example.com" phone="0706666666$1"

    echo "=== RUN $run of $RUNS started $(ts)"
    echo
    echo "-- primary: pg_stat_replication --"
    docker exec "$PRIMARY" psql -U postgres -d threadhaus -c \
      "SELECT * FROM pg_stat_replication;"
    echo "-- primary: pg_replication_slots --"
    docker exec "$PRIMARY" psql -U postgres -d threadhaus -c \
      "SELECT * FROM pg_replication_slots;"
    echo "-- replica: pg_is_in_recovery() (must be true) --"
    docker exec "$REPLICA" psql -U postgres -d threadhaus -c "SELECT pg_is_in_recovery();"
    echo

    echo "-- row counts of all 14 ThreadHaus tables, primary vs replica --"
    local p r
    p=$(docker exec "$PRIMARY" psql -U postgres -d threadhaus -c "$COUNTS_QUERY")
    r=$(docker exec "$REPLICA" psql -U postgres -d threadhaus -c "$COUNTS_QUERY")
    echo "-- primary --"
    echo "$p"
    echo "-- replica --"
    echo "$r"
    if [ "$p" = "$r" ]; then
        echo "row counts identical on primary and replica"
    else
        echo "ROW COUNTS DIFFER:"
        diff <(echo "$p") <(echo "$r") || true
    fi
    echo

    echo "-- insert a new customer on the primary, read it from the replica --"
    docker exec "$PRIMARY" psql -U postgres -d threadhaus -c \
      "INSERT INTO customer (full_name, email, phone, password_hash) VALUES ('Bisi Coker', '$email', '$phone', 'placeholder_hash') RETURNING customer_id, full_name, email;"
    local i found=""
    for i in $(seq 1 30); do
        found=$(docker exec "$REPLICA" psql -U postgres -d threadhaus -Atc \
          "SELECT count(*) FROM customer WHERE email = '$email';")
        if [ "$found" = "1" ]; then
            echo "new row visible on the replica after $i poll(s)"
            break
        fi
        sleep 0.5
    done
    docker exec "$REPLICA" psql -U postgres -d threadhaus -c \
      "SELECT customer_id, full_name, email, phone, created_at FROM customer WHERE email = '$email';"
    echo

    echo "-- INSERT directly on the replica (must be rejected) --"
    docker exec "$REPLICA" psql -U postgres -d threadhaus -c \
      "INSERT INTO customer (full_name, email, phone, password_hash) VALUES ('Blocked Write', 'blocked.run$run@example.com', '0705555555$run', 'placeholder_hash');"
    echo "psql exit code: $? (non-zero means rejected)"
    docker exec "$REPLICA" psql -U postgres -d threadhaus -Atc \
      "SELECT 'rows created on replica by the blocked insert: ' || count(*) FROM customer WHERE email = 'blocked.run$run@example.com';"
    echo
    echo "=== RUN $run finished $(ts)"
}

{
    echo "ThreadHaus PostgreSQL streaming replication - proof check"
    echo "Script: run-replication-check.sh, started $(ts)"
    echo "Commands use docker exec with the container-local Unix socket; no passwords involved."
    echo
} > "$OUT"

SUMMARY=""
for run in $(seq 1 "$RUNS"); do
    run_once "$run" >> "$OUT" 2>&1
    [ "$run" -lt "$RUNS" ] && echo >> "$OUT"
done

{
    echo
    echo "== repeatability =="
    echo "The script ran the full check $RUNS times."
    grep -c 'new row visible on the replica' "$OUT" | \
      sed 's/^/runs where the new row became visible on the replica: /'
    grep -c 'psql exit code: 1 ' "$OUT" | \
      sed 's/^/runs where the replica INSERT was rejected (exit 1): /'
    echo "Both proofs above appearing $RUNS times means the check is repeatable."
    echo "Finished $(ts)"
} >> "$OUT"

echo "run-replication-check: written to $OUT ($RUNS runs)"
