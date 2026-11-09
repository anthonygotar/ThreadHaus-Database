# Portfolio 4: NoSQL and Advanced Data Models

**MIT 8103 Advanced Database Systems**
Anthony Gotar

---

## a. Overview

ThreadHaus uses three data stores in this portfolio, each chosen for what it does best.

**PostgreSQL** keeps everything that needs multi-row transactions, foreign keys and integrity constraints: orders, order items, payments, deliveries, return requests and complaints. These records must be consistent — you cannot have an order_item without a matching order, and a payment must reference a real order. PostgreSQL enforces all of that with FK constraints and transactions.

**MongoDB** holds the product catalogue. Each product, with all its size/colour variants and a precomputed rating summary, is one document. A product page in the web app needs product details, every variant and the rating average in one response. MongoDB delivers that as a single document read.

**Redis** handles short-lived operational data that needs speed and atomic operations: shopping carts (hash), login sessions (string with expiry), the best-sellers ranking (sorted set), and stock reservation (Lua script). These do not need foreign keys or joins. They need sub-millisecond response and built-in expiry.

---

## b. Setup

The environment is defined in `docker-compose.yml`. Both services are started with `docker compose up -d` from the `portfolio-4-nosql/` directory. Full connection instructions are in [`SETUP.md`](SETUP.md).

| Service | Image | Server version | Port |
|---|---|---|---|
| MongoDB | mongo:7.0 | 7.0.45 | 127.0.0.1:27017 |
| Redis | redis:7.4 | 7.4.12 | 127.0.0.1:6379 |

Both ports are published to `127.0.0.1` only (confirmed in `evidence/environment-check.txt` via `ss -ltn`). Neither service is reachable from other machines.

Credentials are in `.env`. That file is excluded from git by `.gitignore`. Copy `.env.example` to `.env` and fill in passwords before starting. See `SETUP.md` for details.

---

## c. MongoDB model

The data model is described in full in [`mongo-model.md`](mongo-model.md). A summary:

**products collection** — one document per product. Each document embeds all variants (sku, size, colour, price, stock_qty) and a precomputed rating summary (average, count).

Example document from migrated data:
```json
{
  "product_id": 1,
  "name": "Ankara Shirt 1",
  "brand": "ThreadHaus",
  "base_price": 17452.15,
  "category_path": ["Men", "Men Tops"],
  "variants": [
    { "variant_id": 3, "sku": "TH-1-L-BLK", "size": "L", "colour": "Black", "price": 21918.41, "stock_qty": 118 },
    { "variant_id": 2, "sku": "TH-1-M-GRN", "size": "M", "colour": "Green", "price": 16197.85, "stock_qty": 135 },
    { "variant_id": 1, "sku": "TH-1-S-WHT", "size": "S", "colour": "White", "price": 19887.15, "stock_qty":  33 },
    { "variant_id": 4, "sku": "TH-1-XL-BLU", "size": "XL", "colour": "Blue",  "price": 22165.55, "stock_qty":  16 },
    { "variant_id": 5, "sku": "TH-1-XXL-RED","size": "XXL","colour": "Red",   "price": 17791.60, "stock_qty":  89 }
  ],
  "rating_summary": { "average": 4, "count": 10 }
}
```

**reviews collection** — one document per review, referencing the product by `product_id`. Reviews are not embedded because they grow without a fixed upper bound. Embedding them would make the product document grow with every new review, inflating every product-page read.

**Reading a product page:**

| | PostgreSQL | MongoDB |
|---|---|---|
| Tables / collections touched | product, product_variant, category (self-join), review (aggregate) | products (one document) |
| Operations needed | 3–4 joins + GROUP BY for rating | Single document read by product_id |


---

## d. Migration and reconciliation

`migrate.sh` exports from PostgreSQL `threadhaus_perf` to MongoDB `threadhaus`. It runs two SQL queries using `psql`, producing JSON Lines output, then pipes each into `mongoimport` via `docker exec`. Both collections are dropped and recreated each run so the script is re-runnable.

The products query builds the embedded document in SQL: it joins product to category, fetches the parent category name for `category_path`, aggregates all non-deleted variants with `json_agg`, and computes the `rating_summary` from the review table. Reviews are exported as-is with `row_to_json`.

Reconciliation (`reconcile.sh`) compares five figures between PostgreSQL and MongoDB (from `evidence/reconciliation.txt`):

| Figure | PostgreSQL | MongoDB | Match |
|---|---|---|---|
| Products | 1,000 | 1,000 | ✓ |
| Variants | 5,000 | 5,000 | ✓ |
| Total stock_qty | 498,044 | 498,044 | ✓ |
| Reviews | 10,000 | 10,000 | ✓ |
| Avg rating | 3.7350 | 3.7350 | ✓ |

All five match.

---

## e. Validation

`validation.js` adds a JSON Schema validator to the products collection using `collMod`. It requires `name`, `category_path`, `base_price` and `variants`. Each variant must have `sku`, `size`, `colour`, `price` and `stock_qty`, and `stock_qty` must be an integer `>= 0`.

From `evidence/validation-test.txt`, inserting a product with `stock_qty: -1` was correctly rejected:

```
Insert correctly rejected.
Error: Document failed validation
```

---

## f. Queries

All five queries are in `queries.js`. Results are in `evidence/mongo-query-results.txt`.

| Query | Business question | PostgreSQL equivalent | Result summary |
|---|---|---|---|
| M1 | In-stock variants in a parent category, chosen size and colour, ordered by price | Q1 (Portfolio 2) | 73 variants returned for Men / M / Black; cheapest at ₦5,787 |
| M2 | Fetch one product with all variants in a single read | — | Product 1 (Ankara Shirt 1), 5 variants in one document read |
| M3 | Top 20 products with ≥5 reviews ordered by average rating | Q6 (Portfolio 2) | Top result: avg 4.4, using embedded rating_summary — no join to reviews |
| M4 | Total stock value (price × stock_qty) grouped by top-level category | — | Men ₦8.6bn, Women ₦8.6bn, Kids ₦3.2bn, Accessories ₦2.9bn |
| M5 | Text search: products whose name or description contains "Kaftan" | — | 63 products matched; requires text index |

