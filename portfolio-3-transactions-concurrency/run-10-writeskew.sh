#!/usr/bin/env bash
# run-10-writeskew.sh
# 10a REPEATABLE READ: write skew — both commit, zero riders available (rule broken).
# 10b SERIALIZABLE: one session aborted; retry sees count=1 and does not proceed.

set -e
cd "$(dirname "$0")"
export PGDATABASE=threadhaus

echo "======================================="
echo "10a: REPEATABLE READ — write skew"
echo "======================================="
bash reset-db.sh

echo ""
echo "--- Setup: set only riders 1 and 2 available ---"
psql -c "UPDATE rider SET is_available = FALSE;"
psql -c "UPDATE rider SET is_available = TRUE WHERE rider_id IN (1, 2);"
psql -c "SELECT rider_id, full_name, is_available FROM rider ORDER BY rider_id;"

psql -f 10a-writeskew-s1.sql > /tmp/s1a.txt 2>&1 &
PID1=$!
psql -f 10a-writeskew-s2.sql > /tmp/s2a.txt 2>&1 &
PID2=$!
wait $PID1; wait $PID2

echo ""; echo "=== S1 output (REPEATABLE READ) ==="; cat /tmp/s1a.txt
echo ""; echo "=== S2 output (REPEATABLE READ) ==="; cat /tmp/s2a.txt
echo ""
echo "--- Final rider availability (BOTH should be FALSE — rule BROKEN) ---"
psql -c "SELECT rider_id, full_name, is_available FROM rider ORDER BY rider_id;"
echo ""
echo "=== CONCLUSION ==="
echo "Both sessions saw count=2, both committed. Zero riders available."
echo "REPEATABLE READ does not prevent write skew."

echo ""
echo "======================================="
echo "10b: SERIALIZABLE — write skew prevented"
echo "======================================="
bash reset-db.sh

echo ""
echo "--- Setup: set only riders 1 and 2 available ---"
psql -c "UPDATE rider SET is_available = FALSE;"
psql -c "UPDATE rider SET is_available = TRUE WHERE rider_id IN (1, 2);"
psql -c "SELECT rider_id, full_name, is_available FROM rider ORDER BY rider_id;"

psql -f 10b-writeskew-s1.sql > /tmp/s1b.txt 2>&1 &
PID1=$!
psql -f 10b-writeskew-s2.sql > /tmp/s2b.txt 2>&1 &
PID2=$!
wait $PID1; wait $PID2

echo ""; echo "=== S1 output (SERIALIZABLE) ==="; cat /tmp/s1b.txt
echo ""; echo "=== S2 output (SERIALIZABLE) ==="; cat /tmp/s2b.txt

echo ""
echo "--- State after first attempt (one session aborted) ---"
psql -c "SELECT rider_id, full_name, is_available FROM rider ORDER BY rider_id;"

echo ""
echo "--- Retry: failed session tries again ---"
psql -f 10b-writeskew-s2-retry.sql 2>&1

echo ""
echo "--- Final state (one rider still available — rule preserved) ---"
psql -c "SELECT rider_id, full_name, is_available FROM rider ORDER BY rider_id;"
echo ""
echo "=== CONCLUSION ==="
echo "SERIALIZABLE aborted one session. Retry saw count=1 and did not proceed."
echo "Rule preserved: at least one rider remains available."
