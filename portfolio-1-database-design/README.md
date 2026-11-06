# Portfolio 1: Database Design and Modelling

**MIT 8103 Advanced Database Systems**
Anthony Gotar

---

## 1. Case Study: ThreadHaus

ThreadHaus is a simulated online clothing store. The scenario models a retail business that sells clothing products in multiple sizes and colours through a web platform. Customers browse a product catalogue, place orders, and pay online or on delivery. The store manages its own inventory, dispatches riders for last-mile delivery, and has internal staff who handle operations and customer support.

**Users of the database:**

- Customers — register, log in, browse products, place orders, make payments, request returns, submit complaints, and write reviews.
- Admins and store managers — manage products, categories, stock, and generate sales reports.
- Delivery riders — are assigned to orders and update delivery status.
- Customer support staff — handle complaints and process return requests.

**Major data stored:**

Customer accounts and delivery addresses; product catalogue organised by category, with variants for each size and colour combination; orders and their line items; payments against orders; delivery assignments and tracking; return requests; complaints; and product reviews.

**Key operations:**

Register and log in; manage products and variants; search the catalogue; place an order and update stock; process payment; assign a rider and track delivery; handle returns and refunds; post reviews; generate sales reports.

---

## 2. Files in This Folder

| File | What it is |
|---|---|
| `schema.sql` | DDL script that creates all 14 tables with constraints and foreign keys. Re-runnable. |
| `sample-data.sql` | INSERT statements loading realistic sample rows (Nigerian names, naira prices). Needs a fresh database. |
| `checks.sql` | Three verification queries: row counts, order totals vs item sums, orders overview join. |
| `constraint-tests.sql` | Five statements that must fail, one per constraint type. Run without ON_ERROR_STOP. |
| `er-diagram.md` | ER diagram in Mermaid format. Renders on GitHub. |
| `evidence/` | Folder of text output files and screenshots from running the scripts. |

---

## 3. ER Diagram

The diagram is in `er-diagram.md` and renders directly on GitHub. An exported image is below.

![ThreadHaus ER Diagram](evidence/er-diagram.png)

**Note on delivery.order_id:** In the Mermaid diagram, `delivery.order_id` is marked only `FK`. Mermaid rejects the combination `FK UK` and throws a parse error. In `schema.sql` the column has `UNIQUE (order_id)`, so an order has at most one delivery. The one-to-zero-or-one cardinality on the relationship line (`||--o|`) also reflects this.


---

## 4. Relational Schema

| Table | Purpose |
|---|---|
| `customer` | Stores registered customer accounts. |
| `address` | Delivery addresses belonging to a customer. A customer can have many. |
| `staff` | Internal staff accounts (admin, manager, support). |
| `rider` | Delivery riders and their availability status. |
| `category` | Product categories. Self-referencing for sub-categories. |
| `product` | Products in the catalogue, linked to a category. |
| `product_variant` | One row per SKU (size + colour combination) for each product. |
| `orders` | An order placed by a customer, linked to a delivery address. |
| `order_item` | Line items within an order. Each row is one variant at a recorded price. |
| `payment` | Payment attempts against an order. One order can have many payments. |
| `delivery` | Delivery assignment for an order. One order has at most one delivery. |
| `return_request` | A return raised against a specific order item. |
| `complaint` | A complaint raised by a customer, optionally assigned to a staff member. |
| `review` | A product review written by a customer. One review per customer per product. |

**Main relationships:**

A customer has many addresses and many orders. Each order belongs to one customer and one address. An order has at least one order item, and each item references one product variant. A product has many variants (one per size/colour). A product belongs to one category; categories can be nested. An order can have many payments (for example, a failed attempt followed by a successful one). Each order has at most one delivery row, enforced by a unique constraint on `delivery.order_id`. A delivery is assigned to one rider. A return request is raised against one order item. Complaints and return requests can be assigned to one staff member.

---

## 5. Keys

**Primary keys:** Every table uses `BIGINT GENERATED ALWAYS AS IDENTITY`. PostgreSQL generates the value; application code cannot override it.

**Foreign keys and delete rules** (read from `schema.sql`):

| FK column | References | On delete |
|---|---|---|
| `address.customer_id` | `customer.customer_id` | CASCADE |
| `category.parent_category_id` | `category.category_id` | RESTRICT |
| `product.category_id` | `category.category_id` | RESTRICT |
| `product_variant.product_id` | `product.product_id` | RESTRICT |
| `orders.customer_id` | `customer.customer_id` | RESTRICT |
| `orders.address_id` | `address.address_id` | RESTRICT |
| `order_item.order_id` | `orders.order_id` | CASCADE |
| `order_item.variant_id` | `product_variant.variant_id` | RESTRICT |
| `payment.order_id` | `orders.order_id` | RESTRICT |
| `delivery.order_id` | `orders.order_id` | RESTRICT |
| `delivery.rider_id` | `rider.rider_id` | RESTRICT (nullable) |
| `return_request.order_item_id` | `order_item.order_item_id` | RESTRICT |
| `return_request.staff_id` | `staff.staff_id` | RESTRICT (nullable) |
| `complaint.customer_id` | `customer.customer_id` | RESTRICT |
| `complaint.staff_id` | `staff.staff_id` | RESTRICT (nullable) |
| `review.customer_id` | `customer.customer_id` | RESTRICT |
| `review.product_id` | `product.product_id` | RESTRICT |

CASCADE is used only on `address.customer_id` and `order_item.order_id`. Everything else is RESTRICT.

**Unique constraints** (read from `schema.sql`):

| Table | Unique constraint |
|---|---|
| `customer` | `email`, `phone` (separate constraints) |
| `staff` | `email` |
| `rider` | `phone` |
| `category` | `name` |
| `product_variant` | `sku`; composite `(product_id, size, colour)` |
| `order_item` | composite `(order_id, variant_id)` |
| `payment` | `reference` |
| `delivery` | `order_id` (enforces one delivery per order) |
| `review` | composite `(customer_id, product_id)` |

---

## 6. Constraints

**CHECK constraints** (read from `schema.sql`):

| Table | Column | Rule |
|---|---|---|
| `staff` | `role` | IN ('admin', 'manager', 'support') |
| `product` | `base_price` | >= 0 |
| `product_variant` | `price` | >= 0 |
| `product_variant` | `stock_qty` | >= 0 |
| `orders` | `status` | IN ('pending', 'paid', 'processing', 'shipped', 'delivered', 'cancelled', 'returned') |
| `orders` | `total_amount` | >= 0 |
| `order_item` | `quantity` | > 0 |
| `order_item` | `unit_price` | >= 0 |
| `payment` | `method` | IN ('card', 'bank_transfer', 'ussd', 'cash_on_delivery') |
| `payment` | `amount` | > 0 |
| `payment` | `status` | IN ('pending', 'successful', 'failed', 'refunded') |
| `delivery` | `status` | IN ('pending', 'assigned', 'picked_up', 'in_transit', 'delivered', 'failed') |
| `return_request` | `status` | IN ('requested', 'approved', 'rejected', 'received', 'refunded') |
| `return_request` | `refund_amount` | >= 0 |
| `complaint` | `status` | IN ('open', 'in_progress', 'resolved', 'closed') |
| `review` | `rating` | BETWEEN 1 AND 5 |

**NOT NULL:** All required columns are NOT NULL. Nullable columns are those that are intentionally optional: `address.is_default` has a default, `delivery.rider_id` and `complaint.staff_id` and `return_request.staff_id` are nullable until assigned, `product.description`, `product.brand`, `payment.reference`, `payment.paid_at`, `review.comment`, and all `deleted_at` columns.

**Constraint tests:** `constraint-tests.sql` runs five statements that must fail: negative `stock_qty`, a rating of 6, a duplicate customer email, deleting a customer who has orders (RESTRICT), and a second delivery for an order that already has one. The output is in `evidence/constraint-tests-output.txt`.

---

## 7. Design Choices

**Identity keys over UUIDs.** I used `BIGINT GENERATED ALWAYS AS IDENTITY` for every primary key. Identity integers are smaller, index faster, and are easier to read in queries. UUIDs would be better for distributed systems where rows are generated on multiple nodes, but ThreadHaus is a single PostgreSQL instance.

**NUMERIC(12,2) for money.** Floating-point types (FLOAT, DOUBLE) cannot represent all decimal fractions exactly and would introduce rounding errors in price calculations. `NUMERIC(12,2)` stores exact decimal values. 12 digits allows prices up to ₦9,999,999,999.99, which covers the range needed.

**CHECK constraints instead of lookup tables for statuses.** Status values like `pending`, `shipped`, `delivered` are short, fixed lists. A separate lookup table would add joins to every query that reads status. CHECK constraints enforce the same rule with less complexity. If the list needs to grow, altering a CHECK is straightforward.

**Soft delete on five tables only.** `customer`, `product`, `product_variant`, `staff`, and `rider` have a `deleted_at TIMESTAMPTZ` column. Soft delete means a deactivated customer's order history is still readable, and a discontinued product variant still shows correctly on old order items. The other tables (orders, payments, deliveries, etc.) are not soft-deleted because those records are audit-critical and should not be hidden.

**order_item.unit_price as a price snapshot.** `product_variant.price` can change over time. If an order item referenced the live price, old orders would silently show the wrong amount. Storing `unit_price` on `order_item` at the time of purchase freezes the price paid. This is also why `orders.total_amount` is denormalised — it records the total at order time.

**Payments separate from orders.** A customer might fail one payment and succeed on a second attempt. Keeping payments in their own table means every attempt is recorded with its status and gateway reference. The orders table only tracks the order lifecycle; the payment table tracks the money.

**Table names orders and return_request.** `ORDER` and `RETURN` are reserved words in SQL. Using them as table names without quoting causes parse errors. I named the tables `orders` and `return_request` to avoid the conflict entirely, so queries do not need quoted identifiers.

---

## 8. Normalisation

I started from a flat order sheet where each row represents one order, with item details crammed into single cells.

**Flat table (unnormalised):**

| order_id | customer_name | customer_phone | customer_email | delivery_address | item_names | sizes | colours | quantities | prices | order_total | payment_method | payment_status | rider_name | rider_phone | delivery_status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Funmi Adebayo | 07011111111 | funmi@example.com | 12 Allen Ave, Lagos | Ankara Shirt, Slim Joggers | M, M | Blue, Black | 1, 2 | 9000, 6500 | 22000.00 | card | successful | Chukwudi Eze | 08031234567 | delivered |

The item_names, sizes, colours, quantities and prices columns hold multiple values per cell. This violates First Normal Form.

---

**1NF — one value per cell, one row per item:**

Split each item onto its own row. The key becomes `(order_id, sku)`.

| order_id | customer_name | customer_phone | customer_email | delivery_address | sku | item_name | size | colour | quantity | unit_price | order_total | payment_method | payment_status | rider_name | rider_phone | delivery_status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Funmi Adebayo | 07011111111 | funmi@example.com | 12 Allen Ave, Lagos | TH-ANK-M-BLU | Ankara Shirt | M | Blue | 1 | 9000.00 | 22000.00 | card | successful | Chukwudi Eze | 08031234567 | delivered |
| 1 | Funmi Adebayo | 07011111111 | funmi@example.com | 12 Allen Ave, Lagos | TH-JOG-M-BLK | Slim Joggers | M | Black | 2 | 6500.00 | 22000.00 | card | successful | Chukwudi Eze | 08031234567 | delivered |

Now every cell holds one value. But item_name, size, colour depend only on `sku`, not on the full key `(order_id, sku)`. Customer columns depend only on `customer_email`. This violates Second Normal Form.

---

**2NF — remove partial dependencies:**

Columns that depend on only part of the key move to their own tables.

- Product columns (item_name, size, colour, unit_price) depend only on `sku` → split into **product_variant**.
- Order columns (customer, address, total, payment, rider, delivery status) depend only on `order_id` → split into **orders**.
- What remains — `(order_id, sku, quantity, unit_price)` — is **order_item**.

**orders:**

| order_id | customer_name | customer_phone | customer_email | delivery_address | order_total | payment_method | payment_status | rider_name | rider_phone | delivery_status |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Funmi Adebayo | 07011111111 | funmi@example.com | 12 Allen Ave, Lagos | 22000.00 | card | successful | Chukwudi Eze | 08031234567 | delivered |

**order_item:**

| order_id | sku | quantity | unit_price |
|---|---|---|---|
| 1 | TH-ANK-M-BLU | 1 | 9000.00 |
| 1 | TH-JOG-M-BLK | 2 | 6500.00 |

**product_variant:**

| sku | item_name | size | colour | price |
|---|---|---|---|---|
| TH-ANK-M-BLU | Ankara Shirt | M | Blue | 9000.00 |
| TH-JOG-M-BLK | Slim Joggers | M | Black | 6500.00 |

No more partial dependencies. But in the orders table, customer_phone and customer_email depend on customer_name (not on order_id). Rider_phone depends on rider_name. These are transitive dependencies, which violates Third Normal Form.

---

**3NF — remove transitive dependencies:**

- Customer columns (name, phone, email) depend on the customer, not the order → split into **customer**.
- Rider columns (name, phone) depend on the rider → split into **rider**.
- Payment columns (method, status) belong to a payment attempt, not the order → split into **payment**.
- Delivery (status, rider) is its own event → split into **delivery**.
- item_name depends on the product, not the variant → split into **product**, keeping only product_id on product_variant.
- Products belong to a category → split into **category**.

The result is a set of clean tables where every non-key column depends on the whole key and nothing but the key.

This maps directly to the 14 tables in `schema.sql`: `customer`, `address`, `staff`, `rider`, `category`, `product`, `product_variant`, `orders`, `order_item`, `payment`, `delivery`, `return_request`, `complaint`, and `review`.

---

## 9. How I Ran and Tested It

PostgreSQL version installed: **18.6**.

I connected as the role `anthonygotar` with environment variables `PGHOST`, `PGUSER`, and `PGDATABASE` set. All commands used plain `psql`.

**Commands used:**

```bash
# Drop and recreate the database
psql -d postgres -c "DROP DATABASE IF EXISTS threadhaus;"
psql -d postgres -c "CREATE DATABASE threadhaus;"

# Run schema and sample data
psql -v ON_ERROR_STOP=1 -f schema.sql
psql -v ON_ERROR_STOP=1 -f sample-data.sql

# Run verification queries
psql -v ON_ERROR_STOP=1 -f checks.sql

# Run constraint tests (no ON_ERROR_STOP — all five errors shown)
psql -f constraint-tests.sql
```

`sample-data.sql` assumes a fresh database with identity columns starting at 1. Run `schema.sql` first on a new database before loading it.

**Evidence files in `evidence/`:**

| File | What it shows |
|---|---|
| `schema-run.txt` | Terminal output of running schema.sql |
| `schema-run.png` | Screenshot of the same |
| `tables.txt` | Output of `\dt` showing all 14 tables |
| `product_variant-structure.txt` | Output of `\d product_variant` |
| `product_variant.png` | Screenshot of the same |
| `orders-structure.txt` | Output of `\d orders` |
| `sample-data-run.txt` | Terminal output of running sample-data.sql |
| `sample-data-run.png` | Screenshot of the same |
| `checks-output.txt` | Output of running checks.sql |
| `checks-output.png` | Screenshot of the same |
| `constraint-tests-output.txt` | All five expected errors from constraint-tests.sql |
| `er-diagram.png` | Exported ER diagram image |

---

## 10. AI Use

I used an AI assistant in this portfolio. The full log of what it did and what I checked or changed is in `AI-USE.md` in the repo root.
