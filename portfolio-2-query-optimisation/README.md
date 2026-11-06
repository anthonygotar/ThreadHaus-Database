# Portfolio 2: Query Processing and Optimisation

**MIT 8103 Advanced Database Systems**
Anthony Gotar

---

## a. Setup

I used a separate database called `threadhaus_perf` for this portfolio. I kept it separate from `threadhaus` (the portfolio 1 database) so that the bulk test data did not interfere with the sample data from portfolio 1, and so I could drop and recreate it freely without touching any schema work.

PostgreSQL version installed: **18.6**.

The database was loaded with `bulk-data.sql`, which generates all data in SQL using `generate_series`, `random()`, and `md5()`. No external files. `setseed(0.42)` at the top makes the data repeatable.

**Actual row counts** (from `evidence/verify-output.txt`):

| Table | Rows |
|---|---|
| customer | 10,000 |
| address | 15,000 |
| staff | 10 |
| rider | 50 |
| category | 12 |
| product | 1,000 |
| product_variant | 5,000 |
| orders | 100,000 |
| order_item | 250,000 |
| payment | 89,331 |
| delivery | 69,042 |
| return_request | 1,586 |
| complaint | 2,000 |
| review | 10,000 |

The review table has 10,000 rows, not the 20,000 originally planned. The seed formula `mod(n*97, 10000)` for customer_id and `mod(n*31, 1000)` for product_id produces at most 10,000 unique (customer, product) pairs before cycling — the UNIQUE constraint on review prevents duplicates, so the insert silently capped at 10,000. The data is still large enough for the optimisation work.

---

## b. The Six Queries

All six queries are in [`queries.sql`](queries.sql). Parameter values were chosen by looking up real data in the database before writing each query.

| Query | Business question | Parameter values used |
|---|---|---|
| Q1 | Catalogue search: in-stock variants in a parent category, for a chosen size and colour, ordered by price | parent_category_id = 1 (Men), size = 'M', colour = 'Black' |
| Q2 | Order history: all orders for one customer with item count and total, newest first | customer_id = 4790 (has 10 orders) |
| Q3 | Best sellers: top 10 variants by total quantity sold in the last 30 days, excluding cancelled orders | last 30 days from now(), status != 'cancelled' |
| Q4 | Monthly sales report: total revenue from successful payments grouped by month | status = 'successful' |
| Q5 | Orders awaiting a rider: orders with status paid or processing that have no delivery row yet, oldest first | status IN ('paid', 'processing'), no delivery row |
| Q6 | Product ratings: average rating and review count per product, minimum 5 reviews, top 20 | min 5 reviews |

---

## c. Baseline

Baseline plans were captured with `EXPLAIN (ANALYZE, BUFFERS)` before any manual indexes were created. Only the 25 automatic PK and UNIQUE constraint indexes existed. Full plans are in `evidence/baseline-plans.txt`.

| Query | Baseline median (ms) | Scan types |
|---|---|---|
| Q1 | 1.71 | Seq Scan on product_variant (5000 rows), Seq Scan on product (1000 rows), Seq Scan on category (12 rows); Hash Join |
| Q2 | 16.89 | Seq Scan on orders (100,000 rows); Index Scan on order_item |
| Q3 | 112.24 | Seq Scan on order_item (250,000 rows), Seq Scan on orders (100,000 rows); Hash Join ×3; HashAggregate |
| Q4 | 98.01 | Seq Scan on payment (89,331 rows); Sort with external merge spill to disk (2,248 kB); GroupAggregate |
| Q5 | 20.85 | Parallel Seq Scan on orders (100,000 rows); Index Only Scan on delivery; Nested Loop Anti Join |
| Q6 | 9.13 | Seq Scan on review (10,000 rows), Seq Scan on product (1,000 rows); Hash Join; HashAggregate |

Three things stood out in the baseline plans. Q2 scanned all 100,000 orders to find 10 rows for a single customer — the orders table had no index on customer_id. Q3 and Q4 were the slowest: Q3 read all 250,000 order_item rows in every execution, and Q4 spilled its sort to disk (external merge, 2,248 kB) because the default work_mem of 4 MB was not enough to hold 85,000 payment rows in memory. Q5 used a Parallel Seq Scan even though only 14,003 of 100,000 orders matched the filter — about 14% selectivity, enough for an index to help.


---

## d. Indexes Tried

9 indexes were tested in total. Full details including dropped index reasons are in `indexes.sql`.

| Index | Target query | What happened | Kept? | Reason |
|---|---|---|---|---|
| `idx_orders_customer_date` on orders(customer_id, order_date DESC) | Q2 | Bitmap Index Scan replaced Seq Scan. 100k→10 rows. | **Kept** | 16.89 ms → 0.80 ms (−95%) |
| `idx_orders_order_date` on orders(order_date) | Q3 | Bitmap Index Scan on orders side. Seq Scan on order_item unchanged. | **Kept** | 112.24 ms → 90.11 ms (−20%) |
| `idx_orders_awaiting` partial on orders(order_date) WHERE status IN ('paid','processing') | Q5 | Index Scan replaced Parallel Seq Scan immediately. | **Kept** | 20.85 ms → 0.73 ms (−97%) |
| `idx_variant_instock` partial on product_variant(size, colour) WHERE stock_qty > 0 AND deleted_at IS NULL | Q1 | Bitmap Index Scan. Confirmed by 10-run re-test in q1-retest.txt. | **Kept** | 2.62 ms → 1.39 ms (−47%) per 10-run re-test |
| `idx_payment_success_paid_at` partial on payment(paid_at) INCLUDE (amount) | Q4 | Planner chose Seq Scan on every run. | **Dropped** | Query reads 95% of payment table (85k of 89k rows). Seq scan beats index at that selectivity. |
| `idx_review_product` on review(product_id) INCLUDE (rating) | Q6 | Planner chose Seq Scan. Median regressed to 13.02 ms. | **Dropped** | review table is 10k rows; seq scan reads the whole table in ~114 pages, faster than index overhead. |
| `idx_variant_product` on product_variant(product_id) | Q1 | Not used by planner. | **Dropped** | product_variant (5k rows) is too small for index to help. |
| `idx_product_category` on product(category_id) | Q1 | Not used by planner. | **Dropped** | product (1k rows) is too small. |
| `idx_order_item_variant` on order_item(variant_id) | Q3 extra | Planner kept Seq Scan. Median regressed to ~95 ms. | **Dropped** | Q3 needs most of order_item (250k rows). Hash join with Seq Scan beats nested loop with index. |

---

## e. Results

Final before and after table. Q1 median from `evidence/q1-retest.txt` (10 runs). Q2–Q6 from step 8 (5 runs).

| Query | Baseline median (ms) | After median (ms) | Change % | Index used |
|---|---|---|---|---|
| Q1 Catalogue search | 1.71 | 1.39 | **−19%** | idx_variant_instock |
| Q2 Order history | 16.89 | 0.80 | **−95%** | idx_orders_customer_date |
| Q3 Best sellers | 112.24 | 90.11 | **−20%** | idx_orders_order_date |
| Q4 Monthly sales | 98.01 | 98.01 | 0% | none |
| Q5 Awaiting rider | 20.85 | 0.73 | **−97%** | idx_orders_awaiting |
| Q6 Product ratings | 9.13 | 9.13 | 0% | none |

