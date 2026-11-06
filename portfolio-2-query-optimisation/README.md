# Portfolio 2: Query Processing and Optimisation

**MIT 8103 Advanced Database Systems**
Anthony Gotar

---

## a. Setup

I used a separate database called `threadhaus_perf` for this portfolio. I kept it separate from `threadhaus` (the portfolio 1 database) so that the bulk test data did not interfere with the sample data from portfolio 1, and so I could drop and recreate it freely without touching any schema work.

PostgreSQL version installed: **18.6** (Ubuntu 18.6-0ubuntu0.26.04.1).

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

