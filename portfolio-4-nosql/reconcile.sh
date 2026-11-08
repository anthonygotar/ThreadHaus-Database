#!/usr/bin/env bash
# reconcile.sh
# Compares counts between PostgreSQL (threadhaus_perf) and MongoDB (threadhaus).
# All five figures must match. Passwords never echoed.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

MONGO_USER=$(grep '^MONGO_INITDB_ROOT_USERNAME' "$ENV_FILE" | cut -d= -f2)
MONGO_PASS=$(grep '^MONGO_INITDB_ROOT_PASSWORD' "$ENV_FILE" | cut -d= -f2)

echo "=== PostgreSQL counts (threadhaus_perf, soft-delete filter applied) ==="
PG_PRODUCTS=$(psql -d threadhaus_perf -t -A -c "SELECT COUNT(*) FROM product WHERE deleted_at IS NULL;")
PG_VARIANTS=$(psql -d threadhaus_perf -t -A -c "SELECT COUNT(*) FROM product_variant WHERE deleted_at IS NULL;")
PG_STOCK=$(psql -d threadhaus_perf -t -A -c "SELECT SUM(stock_qty) FROM product_variant WHERE deleted_at IS NULL;")
PG_REVIEWS=$(psql -d threadhaus_perf -t -A -c "SELECT COUNT(*) FROM review;")
PG_AVG=$(psql -d threadhaus_perf -t -A -c "SELECT ROUND(AVG(rating)::numeric, 4) FROM review;")

echo "  Products:        $PG_PRODUCTS"
echo "  Variants:        $PG_VARIANTS"
echo "  Total stock_qty: $PG_STOCK"
echo "  Reviews:         $PG_REVIEWS"
echo "  Avg rating:      $PG_AVG"

echo ""
echo "=== MongoDB counts (threadhaus) ==="
MG_PRODUCTS=$(docker exec -i threadhaus-mongo mongosh \
  --username "$MONGO_USER" --password "$MONGO_PASS" \
  --authenticationDatabase admin threadhaus --quiet --eval \
  "db.products.countDocuments()" 2>/dev/null | tail -1)

MG_VARIANTS=$(docker exec -i threadhaus-mongo mongosh \
  --username "$MONGO_USER" --password "$MONGO_PASS" \
  --authenticationDatabase admin threadhaus --quiet --eval \
  "db.products.aggregate([{\$unwind:'\$variants'},{\$count:'n'}]).toArray()[0].n" 2>/dev/null | tail -1)

MG_STOCK=$(docker exec -i threadhaus-mongo mongosh \
  --username "$MONGO_USER" --password "$MONGO_PASS" \
  --authenticationDatabase admin threadhaus --quiet --eval \
  "db.products.aggregate([{\$unwind:'\$variants'},{\$group:{_id:null,total:{\$sum:'\$variants.stock_qty'}}}]).toArray()[0].total" 2>/dev/null | tail -1)

MG_REVIEWS=$(docker exec -i threadhaus-mongo mongosh \
  --username "$MONGO_USER" --password "$MONGO_PASS" \
  --authenticationDatabase admin threadhaus --quiet --eval \
  "db.reviews.countDocuments()" 2>/dev/null | tail -1)

MG_AVG=$(docker exec -i threadhaus-mongo mongosh \
  --username "$MONGO_USER" --password "$MONGO_PASS" \
  --authenticationDatabase admin threadhaus --quiet --eval \
  "db.reviews.aggregate([{\$group:{_id:null,avg:{\$avg:'\$rating'}}}]).toArray()[0].avg.toFixed(4)" 2>/dev/null | tail -1 | tr -d "'")

echo "  Products:        $MG_PRODUCTS"
echo "  Variants:        $MG_VARIANTS"
echo "  Total stock_qty: $MG_STOCK"
echo "  Reviews:         $MG_REVIEWS"
echo "  Avg rating:      $MG_AVG"

echo ""
echo "=== Comparison ==="
PASS=true
check() {
  local label="$1" pg="$2" mg="$3"
  if [ "$pg" = "$mg" ]; then
    echo "  MATCH   $label: PG=$pg  MG=$mg"
  else
    echo "  MISMATCH $label: PG=$pg  MG=$mg"
    PASS=false
  fi
}

check "Products"        "$PG_PRODUCTS" "$MG_PRODUCTS"
check "Variants"        "$PG_VARIANTS" "$MG_VARIANTS"
check "Total stock_qty" "$PG_STOCK"    "$MG_STOCK"
check "Reviews"         "$PG_REVIEWS"  "$MG_REVIEWS"
check "Avg rating"      "$PG_AVG"      "$MG_AVG"

echo ""
if [ "$PASS" = true ]; then
  echo "All five figures match."
else
  echo "MISMATCH DETECTED — check migration."
  exit 1
fi
