#!/usr/bin/env bash
# run-04a-oversell-for-update.sh
# Fix A: SELECT ... FOR UPDATE prevents the oversell.
# S2 blocks, then sees stock=0 and rolls back.

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
psql -f 04a-oversell-session1.sql > /tmp/s1.txt 2>&1 &
PID1=$!
psql -f 04a-oversell-session2.sql > /tmp/s2.txt 2>&1 &
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

echo "--- Orders placed (must be 1 new order, not 2) ---"
psql -c "SELECT order_id, customer_id, status FROM orders WHERE order_id > 3;"

echo "--- Order items for variant 3 (new ones only — must be 1 row) ---"
psql -c "SELECT oi.order_item_id, oi.order_id, oi.quantity FROM order_item oi WHERE oi.variant_id = 3 AND oi.order_id > 3;"

echo ""
echo "=== CONCLUSION ==="
echo "SELECT FOR UPDATE caused S2 to wait until S1 committed."
echo "S2 then saw stock=0 and rolled back. No oversell."
