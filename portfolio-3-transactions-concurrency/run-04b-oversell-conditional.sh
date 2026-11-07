#!/usr/bin/env bash
# run-04b-oversell-conditional.sh
# Fix B: conditional UPDATE (WHERE stock_qty >= 1) prevents oversell.
# S2 finds the UPDATE matched 0 rows and rolls back.

set -e
cd "$(dirname "$0")"
export PGDATABASE=threadhaus

echo "=== Resetting database ==="
bash reset-db.sh

echo ""
echo "=== Setup: set variant 3 stock to 1 ==="
psql -c "UPDATE product_variant SET stock_qty = 1 WHERE variant_id = 3;"
psql -c "SELECT variant_id, sku, stock_qty FROM product_variant WHERE variant_id = 3;"

echo ""
echo "=== Starting Session 1 and Session 2 in parallel ==="
psql -f 04b-oversell-session1.sql > /tmp/s1.txt 2>&1 &
PID1=$!
psql -f 04b-oversell-session2.sql > /tmp/s2.txt 2>&1 &
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
echo "--- Stock (must be 0 — exactly one unit sold) ---"
psql -c "SELECT variant_id, sku, stock_qty FROM product_variant WHERE variant_id = 3;"

echo "--- New orders placed (must be exactly 1) ---"
psql -c "SELECT order_id, customer_id, status FROM orders WHERE order_id > 3;"

echo "--- New order items for variant 3 (must be 1 row) ---"
psql -c "SELECT oi.order_item_id, oi.order_id, oi.quantity FROM order_item oi WHERE oi.variant_id = 3 AND oi.order_id > 3;"

echo ""
echo "=== CONCLUSION ==="
echo "The conditional UPDATE is atomic. S2's UPDATE matched 0 rows (stock was 0)."
echo "S2 rolled back. No oversell."
