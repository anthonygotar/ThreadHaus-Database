#!/bin/bash
# Collects the replication evidence for portfolio 5 into
# portfolio-5-distributed-cloud/evidence/. All psql calls here go through
# the local Unix socket inside each container (docker exec), so no password
# is needed or printed anywhere. Only load-threadhaus.sh uses the published
# TCP port, with the password read from .env.

set -u
cd "$(dirname "$0")"

PRIMARY=threadhaus-pg-primary
REPLICA=threadhaus-pg-replica
EVDIR=../evidence
mkdir -p "$EVDIR"

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

total_rows() {
    docker exec "$1" psql -U postgres -d threadhaus -At -F' ' -c "$COUNTS_QUERY" \
        | awk '{s+=$2} END {print s+0}'
}

# ---------------------------------------------------------------- a and b --
{
echo "ThreadHaus PostgreSQL streaming replication - primary and replica status"
echo "Collected: $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo
echo "Commands (psql over the container-local Unix socket, no passwords involved):"
echo "  docker exec $PRIMARY psql -U postgres -d threadhaus -c 'SELECT * FROM pg_stat_replication;'"
echo "  docker exec $PRIMARY psql -U postgres -d threadhaus -c 'SELECT * FROM pg_replication_slots;'"
echo "  docker exec $REPLICA  psql -U postgres -d threadhaus -c 'SELECT pg_is_in_recovery();'"
echo
echo "== a) primary: pg_stat_replication (client_addr, state, sent_lsn, replay_lsn, sync_state) =="
docker exec "$PRIMARY" psql -U postgres -d threadhaus -c "SELECT * FROM pg_stat_replication;"
echo
echo "== a) primary: pg_replication_slots =="
docker exec "$PRIMARY" psql -U postgres -d threadhaus -c "SELECT * FROM pg_replication_slots;"
echo
echo "== b) replica: pg_is_in_recovery() (must be true) =="
docker exec "$REPLICA" psql -U postgres -d threadhaus -c "SELECT pg_is_in_recovery();"
} > "$EVDIR/pg-replication-status.txt" 2>&1

# ---------------------------------------------------------------------- c --
{
echo "ThreadHaus PostgreSQL streaming replication - row counts, primary vs replica"
echo "Collected: $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo
echo "Commands (psql over the container-local Unix socket, no passwords involved):"
echo "  docker exec $PRIMARY psql -U postgres -d threadhaus -c \"<14-table UNION ALL count query, see below>\""
echo "  docker exec $REPLICA  psql -U postgres -d threadhaus -c \"<same query>\""
echo
echo "== waiting for the replica to replay the loaded sample data =="
for i in $(seq 1 60); do
    P_TOTAL=$(total_rows "$PRIMARY")
    R_TOTAL=$(total_rows "$REPLICA")
    if [ "$P_TOTAL" = "$R_TOTAL" ]; then
        echo "replica caught up (total rows across the 14 tables on both sides: $P_TOTAL)"
        break
    fi
    echo "poll $i: primary total rows = $P_TOTAL, replica total rows = $R_TOTAL"
    sleep 0.5
done

echo
echo "== primary: row counts of all 14 ThreadHaus tables =="
P_COUNTS=$(docker exec "$PRIMARY" psql -U postgres -d threadhaus -c "$COUNTS_QUERY")
echo "$P_COUNTS"
echo
echo "== replica: row counts of all 14 ThreadHaus tables =="
R_COUNTS=$(docker exec "$REPLICA" psql -U postgres -d threadhaus -c "$COUNTS_QUERY")
echo "$R_COUNTS"
echo
echo "== compare the two outputs =="
if [ "$P_COUNTS" = "$R_COUNTS" ]; then
    echo "the outputs are identical, so all 14 row counts match on primary and replica"
else
    echo "DIFFERENCE FOUND:"
    diff <(echo "$P_COUNTS") <(echo "$R_COUNTS") || true
fi
} > "$EVDIR/pg-replica-counts.txt" 2>&1

# ---------------------------------------------------------------------- d --
{
echo "ThreadHaus PostgreSQL streaming replication - insert on primary, read from replica"
echo "Collected: $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo
echo "Commands (psql over the container-local Unix socket, no passwords involved):"
echo "  docker exec $PRIMARY psql -U postgres -d threadhaus -c \"INSERT INTO customer ... RETURNING customer_id, full_name, email, phone;\""
echo "  poll: docker exec $REPLICA psql -U postgres -d threadhaus -Atc \"SELECT count(*) FROM customer WHERE email = 'adaeze.okafor@example.com.ng';\""
echo "  docker exec $REPLICA psql -U postgres -d threadhaus -c \"SELECT customer_id, full_name, email, phone, created_at FROM customer WHERE email = 'adaeze.okafor@example.com.ng';\""
echo
echo "== insert one new customer on the primary =="
docker exec "$PRIMARY" psql -U postgres -d threadhaus -c "INSERT INTO customer (full_name, email, phone, password_hash) VALUES ('Adaeze Okafor', 'adaeze.okafor@example.com.ng', '07099998888', 'placeholder_hash') RETURNING customer_id, full_name, email, phone;"
echo
echo "== poll the replica until the row appears (streaming replication is asynchronous) =="
for i in $(seq 1 30); do
    FOUND=$(docker exec "$REPLICA" psql -U postgres -d threadhaus -Atc "SELECT count(*) FROM customer WHERE email = 'adaeze.okafor@example.com.ng';")
    echo "poll $i: replica rows matching the new customer email = $FOUND"
    if [ "$FOUND" = "1" ]; then break; fi
    sleep 0.5
done
echo
echo "== read the new customer from the replica =="
docker exec "$REPLICA" psql -U postgres -d threadhaus -c "SELECT customer_id, full_name, email, phone, created_at FROM customer WHERE email = 'adaeze.okafor@example.com.ng';"
echo
echo "== the same row on the primary, for comparison =="
docker exec "$PRIMARY" psql -U postgres -d threadhaus -c "SELECT customer_id, full_name, email, phone, created_at FROM customer WHERE email = 'adaeze.okafor@example.com.ng';"
} > "$EVDIR/pg-replication-insert.txt" 2>&1

# ---------------------------------------------------------------------- e --
{
echo "ThreadHaus PostgreSQL streaming replication - the replica rejects writes"
echo "Collected: $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo
echo "Command (psql over the container-local Unix socket, no passwords involved):"
echo "  docker exec $REPLICA psql -U postgres -d threadhaus -c \"INSERT INTO customer (full_name, email, phone, password_hash) VALUES ('Blocked Write', 'blocked.write@example.com.ng', '07077777777', 'placeholder_hash');\""
echo
echo "== confirm the replica is in recovery before trying to write =="
docker exec "$REPLICA" psql -U postgres -d threadhaus -c "SELECT pg_is_in_recovery();"
echo
echo "== try an INSERT directly on the replica =="
docker exec "$REPLICA" psql -U postgres -d threadhaus -c "INSERT INTO customer (full_name, email, phone, password_hash) VALUES ('Blocked Write', 'blocked.write@example.com.ng', '07077777777', 'placeholder_hash');"
echo "psql exit code: $?"
echo
echo "== confirm no row was created on either side =="
docker exec "$REPLICA" psql -U postgres -d threadhaus -c "SELECT count(*) AS replica_rows_matching FROM customer WHERE email = 'blocked.write@example.com.ng';"
docker exec "$PRIMARY" psql -U postgres -d threadhaus -c "SELECT count(*) AS primary_rows_matching FROM customer WHERE email = 'blocked.write@example.com.ng';"
} > "$EVDIR/pg-replica-readonly.txt" 2>&1

echo "collect-evidence: evidence written to $EVDIR (pg-replication-status.txt, pg-replica-counts.txt, pg-replication-insert.txt, pg-replica-readonly.txt)"
