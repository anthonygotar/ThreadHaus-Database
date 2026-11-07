#!/usr/bin/env bash
# run-05-deadlock.sh
# Demonstrates a deadlock between two sessions locking variants in opposite order.
# PostgreSQL detects the cycle and aborts one session with "deadlock detected".

set -e
cd "$(dirname "$0")"
export PGDATABASE=threadhaus

echo "=== Resetting database ==="
bash reset-db.sh

echo ""
echo "=== Starting Session 1 and Session 2 in parallel ==="
psql -f 05-deadlock-session1.sql > /tmp/s1.txt 2>&1 &
PID1=$!
psql -f 05-deadlock-session2.sql > /tmp/s2.txt 2>&1 &
PID2=$!

wait $PID1
wait $PID2

echo ""
echo "=== Session 1 output ==="
cat /tmp/s1.txt

echo ""
echo "=== Session 2 output ==="
cat /tmp/s2.txt

echo ""
echo "=== Final state ==="
echo "--- Stock for variants 3 and 6 ---"
psql -c "SELECT variant_id, sku, stock_qty FROM product_variant WHERE variant_id IN (3, 6);"

echo "--- New orders (one session committed, one was the deadlock victim) ---"
psql -c "SELECT order_id, customer_id, status, total_amount FROM orders WHERE order_id > 3;"

echo ""
echo "=== CONCLUSION ==="
echo "One session got the ERROR: deadlock detected and was aborted."
echo "The other session committed successfully."
echo "Only one order was placed."
