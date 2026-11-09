#!/usr/bin/env bash
# 05-persistence.sh
# Shows that Redis appendonly persistence survives a container restart.
# Creates keys, restarts the container, then confirms keys and TTLs are intact.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REDIS_PASS=$(grep '^REDIS_PASSWORD' "$SCRIPT_DIR/../.env" | cut -d= -f2)

R() { docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis redis-cli "$@"; }

echo "=== 1. Confirm appendonly is on ==="
R CONFIG GET appendonly

echo ""
echo "=== 2. Create test keys ==="
R SET session:persist_test 7777 EX 3600
R HSET cart:persist_test 3 2 8 1
R EXPIRE cart:persist_test 86400

echo "--- TTL before restart ---"
echo "session:persist_test TTL:" $(R TTL session:persist_test)
echo "cart:persist_test TTL:" $(R TTL cart:persist_test)

echo ""
echo "=== 3. Restart the container ==="
docker restart threadhaus-redis
echo "Waiting 5s for Redis to come back up..."
sleep 5

echo ""
echo "=== 4. Check keys survived the restart ==="
echo "--- session:persist_test ---"
R GET session:persist_test
echo "TTL:" $(R TTL session:persist_test)

echo "--- cart:persist_test ---"
R HGETALL cart:persist_test
echo "TTL:" $(R TTL cart:persist_test)

echo ""
echo "=== 5. Cleanup ==="
R DEL session:persist_test cart:persist_test
echo "Done. Keys deleted."
