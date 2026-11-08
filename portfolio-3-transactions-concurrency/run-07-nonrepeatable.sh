#!/usr/bin/env bash
# run-07-nonrepeatable.sh
# 07a: READ COMMITTED — non-repeatable read (S1 sees S2's committed change).
# 07b: REPEATABLE READ — snapshot prevents the change being seen; UPDATE then fails.

set -e
cd "$(dirname "$0")"
export PGDATABASE=threadhaus

echo "=========================================="
echo "07a: READ COMMITTED — non-repeatable read"
echo "=========================================="
bash reset-db.sh

echo ""
echo "--- Baseline price of variant 3 ---"
psql -c "SELECT variant_id, sku, price FROM product_variant WHERE variant_id = 3;"

psql -f 07a-nonrepeatable-s1.sql > /tmp/s1a.txt 2>&1 &
PID1=$!
psql -f 07-nonrepeatable-s2.sql   > /tmp/s2a.txt 2>&1 &
PID2=$!
wait $PID1; wait $PID2

echo ""; echo "=== S1 output (READ COMMITTED) ==="; cat /tmp/s1a.txt
echo ""; echo "=== S2 output ==="; cat /tmp/s2a.txt
echo ""
echo "--- Final price (should be baseline + 500) ---"
psql -c "SELECT variant_id, sku, price FROM product_variant WHERE variant_id = 3;"

echo ""
echo "=========================================="
echo "07b: REPEATABLE READ — no non-repeatable read; UPDATE fails"
echo "=========================================="
bash reset-db.sh

echo ""
echo "--- Baseline price of variant 3 ---"
psql -c "SELECT variant_id, sku, price FROM product_variant WHERE variant_id = 3;"

psql -f 07b-nonrepeatable-s1.sql > /tmp/s1b.txt 2>&1 &
PID1=$!
psql -f 07-nonrepeatable-s2.sql   > /tmp/s2b.txt 2>&1 &
PID2=$!
wait $PID1; wait $PID2

echo ""; echo "=== S1 output (REPEATABLE READ) ==="; cat /tmp/s1b.txt
echo ""; echo "=== S2 output ==="; cat /tmp/s2b.txt
echo ""
echo "--- Final price (only S2's +500 committed; S1 was rolled back) ---"
psql -c "SELECT variant_id, sku, price FROM product_variant WHERE variant_id = 3;"
