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

