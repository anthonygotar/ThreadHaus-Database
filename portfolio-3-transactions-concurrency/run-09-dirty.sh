#!/usr/bin/env bash
# run-09-dirty.sh
# Demonstrates that PostgreSQL does not allow dirty reads even at READ UNCOMMITTED.
# S1 updates price to 99999 without committing. S2 reads at READ UNCOMMITTED.
# S2 still sees the old committed price (6500), not the dirty value.

set -e
cd "$(dirname "$0")"
export PGDATABASE=threadhaus

echo "================================"
echo "09: Dirty read attempt"
echo "================================"
bash reset-db.sh

echo ""
echo "--- Committed price of variant 3 before test ---"
psql -c "SELECT variant_id, sku, price FROM product_variant WHERE variant_id = 3;"

psql -f 09-dirty-s1.sql > /tmp/s1.txt 2>&1 &
PID1=$!
psql -f 09-dirty-s2.sql > /tmp/s2.txt 2>&1 &
PID2=$!
wait $PID1; wait $PID2

echo ""; echo "=== S1 output (update then rollback) ==="; cat /tmp/s1.txt
echo ""; echo "=== S2 output (READ UNCOMMITTED) ==="; cat /tmp/s2.txt

echo ""
echo "--- Final price (must still be 6500 — S1 rolled back) ---"
psql -c "SELECT variant_id, sku, price FROM product_variant WHERE variant_id = 3;"
echo ""
echo "=== CONCLUSION ==="
echo "S2 saw 6500.00 (the committed price), not 99999.00 (the dirty value)."
echo "PostgreSQL does not implement dirty reads. READ UNCOMMITTED behaves"
echo "the same as READ COMMITTED."
