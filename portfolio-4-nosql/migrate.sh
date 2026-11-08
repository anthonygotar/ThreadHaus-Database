#!/usr/bin/env bash
# migrate.sh
# Exports products and reviews from PostgreSQL (threadhaus_perf) to MongoDB (threadhaus).
# Uses psql to produce JSON Lines, then mongoimport via docker exec.
# Re-runnable: drops and recreates both collections each time.
# Passwords are read from .env — never echoed or logged.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env not found. Copy .env.example to .env and fill in credentials."
  exit 1
fi

MONGO_USER=$(grep '^MONGO_INITDB_ROOT_USERNAME' "$ENV_FILE" | cut -d= -f2)
MONGO_PASS=$(grep '^MONGO_INITDB_ROOT_PASSWORD' "$ENV_FILE" | cut -d= -f2)

echo "=== Exporting products from PostgreSQL ==="
# One JSON object per line (JSON Lines format).
# category_path: array [parent_name, child_name], or just [child_name] for top-level categories.
# variants: embedded array of all non-deleted variants.
# rating_summary: precomputed from the review table.
psql -d threadhaus_perf -t -A -F '' -c "
SELECT row_to_json(doc)
FROM (
  SELECT
    p.product_id,
    p.name,
    COALESCE(p.brand, '') AS brand,
    p.base_price::float AS base_price,
    COALESCE(p.description, '') AS description,
    -- category_path: [parent, child] or [child] for top-level
    CASE
      WHEN cp.name IS NOT NULL THEN ARRAY[cp.name, c.name]
      ELSE ARRAY[c.name]
    END AS category_path,
    -- embedded variants (non-deleted)
    COALESCE(
      (SELECT json_agg(
        json_build_object(
          'variant_id', pv.variant_id,
          'sku',        pv.sku,
          'size',       pv.size,
          'colour',     pv.colour,
          'price',      pv.price::float,
          'stock_qty',  pv.stock_qty
        )
      )
      FROM product_variant pv
      WHERE pv.product_id = p.product_id AND pv.deleted_at IS NULL),
      '[]'::json
    ) AS variants,
    -- precomputed rating summary
    json_build_object(
      'average', COALESCE(ROUND(AVG(r.rating)::numeric, 2)::float, 0),
      'count',   COUNT(r.review_id)
    ) AS rating_summary
  FROM product p
  JOIN category c ON c.category_id = p.category_id
  LEFT JOIN category cp ON cp.category_id = c.parent_category_id
  LEFT JOIN review r ON r.product_id = p.product_id
  WHERE p.deleted_at IS NULL
  GROUP BY p.product_id, p.name, p.brand, p.base_price, p.description,
           c.name, cp.name
  ORDER BY p.product_id
) doc
" > /tmp/th_products.jsonl
echo "Exported $(wc -l < /tmp/th_products.jsonl) product documents"

echo "=== Exporting reviews from PostgreSQL ==="
psql -d threadhaus_perf -t -A -F '' -c "
SELECT row_to_json(doc)
FROM (
  SELECT
    review_id,
    product_id,
    customer_id,
    rating,
    COALESCE(comment, '') AS comment,
    created_at
  FROM review
  ORDER BY review_id
) doc
" > /tmp/th_reviews.jsonl
echo "Exported $(wc -l < /tmp/th_reviews.jsonl) review documents"

echo "=== Loading into MongoDB ==="
# Copy files into container (mongoimport reads stdin)
cat /tmp/th_products.jsonl | docker exec -i threadhaus-mongo \
  mongoimport \
    --username "$MONGO_USER" \
    --password "$MONGO_PASS" \
    --authenticationDatabase admin \
    --db threadhaus \
    --collection products \
    --drop \
    2>&1

cat /tmp/th_reviews.jsonl | docker exec -i threadhaus-mongo \
  mongoimport \
    --username "$MONGO_USER" \
    --password "$MONGO_PASS" \
    --authenticationDatabase admin \
    --db threadhaus \
    --collection reviews \
    --drop \
    2>&1

echo "=== Migration complete ==="
# Clean up temp files
rm -f /tmp/th_products.jsonl /tmp/th_reviews.jsonl
