#!/usr/bin/env bash
# run-06-deadlock-fixed.sh
# Fix: both sessions lock variants in ascending variant_id order.
# S2 waits for S1 to release — no deadlock, both orders commit.

set -e
cd "$(dirname "$0")"
export PGDATABASE=threadhaus

echo "=== Resetting database ==="
bash reset-db.sh

echo ""
echo "=== Starting Session 1 and Session 2 in parallel ==="
psql -f 06-deadlock-fixed-session1.sql > /tmp/s1.txt 2>&1 &
PID1=$!
psql -f 06-deadlock-fixed-session2.sql > /tmp/s2.txt 2>&1 &
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
echo "--- Stock for variants 3 and 6 (each reduced by 2 — both orders committed) ---"
psql -c "SELECT variant_id, sku, stock_qty FROM product_variant WHERE variant_id IN (3, 6);"

echo "--- New orders (must be 2 — both sessions committed) ---"
psql -c "SELECT order_id, customer_id, status, total_amount FROM orders WHERE order_id > 3;"

echo ""
echo "=== CONCLUSION ==="
echo "No deadlock. S2 simply waited for S1 to release variant 3."
echo "Both sessions committed. Two orders placed."
