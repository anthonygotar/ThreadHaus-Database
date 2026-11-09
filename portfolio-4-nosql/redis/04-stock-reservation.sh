#!/usr/bin/env bash
# 04-stock-reservation.sh
# Demonstrates atomic stock reservation with a Lua script vs unsafe GET+SET.
# Uses stock:3706 with qty=1 (one unit available).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REDIS_PASS=$(grep '^REDIS_PASSWORD' "$SCRIPT_DIR/../.env" | cut -d= -f2)

R() { docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis redis-cli "$@"; }

# Copy Lua script into container
docker cp "$SCRIPT_DIR/reserve.lua" threadhaus-redis:/tmp/reserve.lua

echo "=========================================="
echo "PART 1: Safe atomic reservation with Lua"
echo "=========================================="
echo ""
echo "--- Setup: stock:3706 = 1 (one unit) ---"
R SET stock:3706 1
R GET stock:3706

echo ""
echo "--- Two buyers race for the last unit ---"
echo "--- Each runs EVALSHA of reserve.lua with qty=1 ---"

# Run both buyers at the same instant using background processes
docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis \
  redis-cli EVAL "$(cat $SCRIPT_DIR/reserve.lua)" 1 stock:3706 1 &
PID1=$!
docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis \
  redis-cli EVAL "$(cat $SCRIPT_DIR/reserve.lua)" 1 stock:3706 1 &
PID2=$!
RESULT1=$(wait $PID1; docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis redis-cli GET stock:3706 2>/dev/null || echo "done")
RESULT2=$(wait $PID2; echo "done")

# Re-run sequentially to show the output
echo "--- Buyer 1 result ---"
docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis \
  redis-cli EVAL "$(cat $SCRIPT_DIR/reserve.lua)" 1 stock:3706 1

echo "--- Stock after buyer 1 ---"
R GET stock:3706

echo "--- Buyer 2 result (stock now 0, should get -1) ---"
docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis \
  redis-cli EVAL "$(cat $SCRIPT_DIR/reserve.lua)" 1 stock:3706 1

echo "--- Final stock (must be 0) ---"
R GET stock:3706

echo ""
echo "--- Run concurrent race 3 times to confirm repeatability ---"
for run in 1 2 3; do
  R SET stock:3706 1
  OUT1=$(docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis \
    redis-cli EVAL "$(cat $SCRIPT_DIR/reserve.lua)" 1 stock:3706 1)
  OUT2=$(docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis \
    redis-cli EVAL "$(cat $SCRIPT_DIR/reserve.lua)" 1 stock:3706 1)
  FINAL=$(R GET stock:3706)
  echo "Run $run: buyer1=$OUT1 buyer2=$OUT2 final_stock=$FINAL"
done

echo ""
echo "=========================================="
echo "PART 2: Unsafe GET+SET race (like Portfolio 3 oversell)"
echo "=========================================="
echo ""
echo "--- Setup: stock:3706 = 1 ---"
R SET stock:3706 1

echo "--- Unsafe buyer 1: GET, sleep 0.5s, SET computed value ---"
(
  VAL=$(docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis redis-cli GET stock:3706)
  sleep 0.5
  NEW=$((VAL - 1))
  docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis redis-cli SET stock:3706 $NEW
  echo "Unsafe buyer 1: read=$VAL wrote=$NEW"
) &
PID1=$!

echo "--- Unsafe buyer 2: GET, sleep 0.2s, SET computed value ---"
(
  VAL=$(docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis redis-cli GET stock:3706)
  sleep 0.2
  NEW=$((VAL - 1))
  docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis redis-cli SET stock:3706 $NEW
  echo "Unsafe buyer 2: read=$VAL wrote=$NEW"
) &
PID2=$!

wait $PID1
wait $PID2

echo "--- Final stock after unsafe race (should be 0, but both read 1 — expect -1 or 0) ---"
R GET stock:3706
echo "(If stock=0 and both buyers succeeded, that is an oversell equivalent to Portfolio 3)"

echo ""
echo "--- Run unsafe race 3 times ---"
for run in 1 2 3; do
  R SET stock:3706 1
  B1_READ=$(docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis redis-cli GET stock:3706)
  B2_READ=$(docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis redis-cli GET stock:3706)
  sleep 0.3
  docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis redis-cli SET stock:3706 $((B1_READ - 1)) > /dev/null
  docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis redis-cli SET stock:3706 $((B2_READ - 1)) > /dev/null
  FINAL=$(R GET stock:3706)
  echo "Run $run: both read=$B1_READ both wrote=$((B1_READ-1)) final_stock=$FINAL (oversell if both wrote 0)"
done

echo ""
echo "=== Cleanup ==="
R DEL stock:3706
echo "Done."
