#!/usr/bin/env bash
# run-03-oversell-unsafe.sh
# Demonstrates a lost update / oversell race under READ COMMITTED.
# Two sessions each read stock=1 and both succeed in placing an order.

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
psql -f 03-oversell-session1.sql > /tmp/s1.txt 2>&1 &
PID1=$!
psql -f 03-oversell-session2.sql > /tmp/s2.txt 2>&1 &
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
echo "--- Stock (stock_qty is 0 but TWO orders were placed — OVERSELL) ---"
psql -c "SELECT variant_id, sku, stock_qty FROM product_variant WHERE variant_id = 3;"

echo "--- Order items sold for variant 3 (must be 2 rows — LOST UPDATE) ---"
psql -c "SELECT oi.order_item_id, oi.order_id, oi.quantity FROM order_item oi WHERE oi.variant_id = 3;"

echo ""
echo "=== CONCLUSION ==="
echo "Both sessions read stock=1 before either committed."
echo "Both wrote stock=0. S2 overwrote S1's stock update — lost update."
echo "Result: stock=0 but 2 units sold. This is an oversell."
