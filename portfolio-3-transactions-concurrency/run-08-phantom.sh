#!/usr/bin/env bash
# run-08-phantom.sh
# 08a READ COMMITTED: second count is higher (phantom read).
# 08b REPEATABLE READ: second count unchanged (snapshot blocks phantom).

set -e
cd "$(dirname "$0")"
export PGDATABASE=threadhaus

echo "================================"
echo "08a: READ COMMITTED — phantom read"
echo "================================"
bash reset-db.sh

echo ""
echo "--- Baseline order count for customer 1 ---"
psql -c "SELECT COUNT(*) AS order_count FROM orders WHERE customer_id = 1;"

psql -f 08a-phantom-s1.sql > /tmp/s1a.txt 2>&1 &
PID1=$!
psql -f 08-phantom-s2.sql  > /tmp/s2a.txt 2>&1 &
PID2=$!
wait $PID1; wait $PID2

echo ""; echo "=== S1 output (READ COMMITTED) ==="; cat /tmp/s1a.txt
echo ""; echo "=== S2 output ==="; cat /tmp/s2a.txt

echo ""
echo "================================"
echo "08b: REPEATABLE READ — no phantom"
echo "================================"
bash reset-db.sh

echo ""
echo "--- Baseline order count for customer 1 ---"
psql -c "SELECT COUNT(*) AS order_count FROM orders WHERE customer_id = 1;"

psql -f 08b-phantom-s1.sql > /tmp/s1b.txt 2>&1 &
PID1=$!
psql -f 08-phantom-s2.sql  > /tmp/s2b.txt 2>&1 &
PID2=$!
wait $PID1; wait $PID2

echo ""; echo "=== S1 output (REPEATABLE READ) ==="; cat /tmp/s1b.txt
echo ""; echo "=== S2 output ==="; cat /tmp/s2b.txt
echo ""
echo "--- Final order count (S2's insert is committed but S1 did not see it) ---"
psql -c "SELECT COUNT(*) AS order_count FROM orders WHERE customer_id = 1;"
