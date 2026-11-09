#!/usr/bin/env bash
# 03-bestsellers.sh
# Build a sorted set bestsellers:30d from PostgreSQL data (same as Q3).
# Load top variants by quantity sold, show ranking, reconcile with PostgreSQL,
# then simulate a new sale with ZINCRBY. Also show a product view counter.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REDIS_PASS=$(grep '^REDIS_PASSWORD' "$SCRIPT_DIR/../.env" | cut -d= -f2)

R() { docker exec -e REDISCLI_AUTH="$REDIS_PASS" threadhaus-redis redis-cli "$@"; }

echo "=== 1. Build bestsellers:30d from PostgreSQL (Q3 equivalent) ==="
echo "--- PostgreSQL top 10 by qty_sold last 30 days, excl. cancelled ---"
export PGDATABASE=threadhaus_perf
psql -t -A -c "
SELECT oi.variant_id, SUM(oi.quantity) AS qty_sold
FROM order_item oi
JOIN orders o ON o.order_id = oi.order_id
WHERE o.order_date >= now() - interval '30 days'
  AND o.status != 'cancelled'
GROUP BY oi.variant_id
ORDER BY qty_sold DESC
LIMIT 10;" > /tmp/bestsellers.txt
cat /tmp/bestsellers.txt

echo ""
echo "--- Loading into Redis sorted set bestsellers:30d ---"
R DEL bestsellers:30d
while IFS='|' read -r variant_id qty; do
  R ZADD bestsellers:30d "$qty" "variant:$variant_id"
done < /tmp/bestsellers.txt

echo ""
echo "=== 2. ZREVRANGE top 10 with scores ==="
R ZREVRANGE bestsellers:30d 0 9 WITHSCORES

echo ""
echo "=== 3. Reconciliation: PostgreSQL top 10 vs Redis ranking ==="
echo "PostgreSQL top 10 (variant_id | qty_sold):"
cat /tmp/bestsellers.txt
echo ""
echo "Redis top 10 (variant:id | score):"
R ZREVRANGE bestsellers:30d 0 9 WITHSCORES

echo ""
echo "=== 4. Simulate new sale: ZINCRBY variant $(head -1 /tmp/bestsellers.txt | cut -d'|' -f1) by 5 ==="
TOP_VARIANT=$(head -1 /tmp/bestsellers.txt | cut -d'|' -f1)
echo "Before: variant:$TOP_VARIANT score = $(R ZSCORE bestsellers:30d "variant:$TOP_VARIANT")"
R ZINCRBY bestsellers:30d 5 "variant:$TOP_VARIANT"
echo "After ZINCRBY 5:"
R ZREVRANGE bestsellers:30d 0 2 WITHSCORES

echo ""
echo "=== 5. Product view counter with INCR ==="
R SET views:product:1 0
R INCR views:product:1
R INCR views:product:1
R INCR views:product:1
echo "Product 1 views: $(R GET views:product:1)"

echo ""
echo "=== Cleanup ==="
R DEL bestsellers:30d views:product:1
rm -f /tmp/bestsellers.txt
echo "Done."
