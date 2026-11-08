# MongoDB Data Model — ThreadHaus Portfolio 4

## Collections

### products

One document per product. Each document embeds all variants for that product and a precomputed rating summary.

```json
{
  "product_id": 1,
  "name": "Ankara Shirt 1",
  "brand": "ThreadHaus",
  "base_price": 17452.15,
  "description": "Description for product 1",
  "category_path": ["Men", "Men Tops"],
  "variants": [
    { "variant_id": 1, "sku": "TH-1-S-BLU", "size": "S", "colour": "Blue",  "price": 18247.50, "stock_qty": 143 },
    { "variant_id": 2, "sku": "TH-1-M-BLK", "size": "M", "colour": "Black", "price": 17890.00, "stock_qty":  87 },
    { "variant_id": 3, "sku": "TH-1-L-RED", "size": "L", "colour": "Red",   "price": 19100.30, "stock_qty":   0 },
    { "variant_id": 4, "sku": "TH-1-XL-WHT","size": "XL","colour": "White", "price": 16500.00, "stock_qty": 200 },
    { "variant_id": 5, "sku": "TH-1-XXL-GRN","size":"XXL","colour":"Green", "price": 17000.00, "stock_qty":  55 }
  ],
  "rating_summary": {
    "average": 4.20,
    "count": 10
  }
}
```

(Example document taken from migrated data. Exact values depend on the bulk data seed.)

### reviews

One document per review. The product is referenced by `product_id` rather than embedded.

```json
{
  "review_id": 1,
  "product_id": 1,
  "customer_id": 97,
  "rating": 5,
  "comment": "Review comment 97-1",
  "created_at": "2026-11-06T07:00:00.000Z"
}
```

---

## Why variants are embedded, reviews are referenced

**Variants are embedded.** A product has exactly 5 variants in this dataset and that number is bounded. Every product-page request needs all variants (sizes, colours, prices, stock). Embedding them in the product document means a product page is one document read with no joins.

**Reviews are referenced.** Reviews grow without a fixed upper bound — a popular product can accumulate thousands of reviews over time. Embedding them in the product document would make that document grow unboundedly, increasing read cost for every product lookup even when reviews are not needed. Storing reviews in a separate collection keeps the product document small and lets the application page through reviews independently.

The `rating_summary` field (average and count) is precomputed at migration time and embedded in the product document. This allows fast top-rated queries without aggregating the reviews collection. The trade-off is that the summary goes stale when a new review is added and must be updated at write time.

---

## Reading a product page: PostgreSQL vs MongoDB

| | PostgreSQL | MongoDB |
|---|---|---|
| Tables / collections touched | product, product_variant, category (self-join for parent), review (aggregate) | products (one document) |
| Operations | 3–4 joins + GROUP BY for rating | Single document read |
| Index lookups | PK on product, FK joins on variant and category | \_id or product_id index |
| Consistency | Foreign keys enforce referential integrity | No FK; rating_summary can be stale |

---

## What is lost or harder compared to PostgreSQL

- **No foreign keys.** MongoDB does not enforce that `reviews.product_id` points to a real product. Orphaned reviews are possible if a product is deleted.
- **Duplicated category names.** The `category_path` array stores names as strings (e.g. `["Men", "Men Tops"]`). In PostgreSQL the category name lives in one place. In MongoDB, renaming a category requires updating every product document in that category.
- **Stale rating summary.** The `rating_summary` is computed at migration time. When a new review is added, the application must also update `products.rating_summary`. If it forgets, the summary is wrong. PostgreSQL computes the aggregate on the fly from the review table, so it is always correct.
- **No multi-document transactions by default.** Moving stock between warehouses or adjusting both a product and its variants atomically requires a multi-document transaction (supported in MongoDB 4+, but with more overhead than PostgreSQL).
