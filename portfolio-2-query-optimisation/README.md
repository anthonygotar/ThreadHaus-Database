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


---

## f. Performance Analysis

**Q2 and Q5 improved the most.** Q2 went from 16.89 ms to 0.80 ms (−95%) and Q5 from 20.85 ms to 0.73 ms (−97%). Both had the same underlying problem: a full sequential scan of 100,000 orders to find a small subset. For Q2 the filter was `customer_id = 4790`, which matched exactly 10 rows — 0.01% of the table. `idx_orders_customer_date` on `(customer_id, order_date DESC)` lets the planner jump directly to those 10 rows with a Bitmap Index Scan, then sort by order_date at no extra cost because order_date is the second key in the index. For Q5 the filter was `status IN ('paid', 'processing')`, which matched 14,003 rows (14% of the table) — selective enough for an index to win. The partial index `idx_orders_awaiting` only stores rows that satisfy the WHERE clause, so it is small (328 kB) and the index scan reads only the matching rows in order_date sequence, eliminating both the filter pass and the sort entirely. The planner switched from a Parallel Seq Scan with a Gather Merge node to a plain Index Scan in a single pass.

**Q3 improved moderately** (−20%, 112.24 ms → 90.11 ms). The bottleneck for Q3 is the Seq Scan on order_item: all 250,000 rows must be read to find the ~19,000 that join to orders in the last 30 days. `idx_orders_order_date` helped only the orders side of the hash join, reducing the hash table from 100,000 rows to roughly 7,750 (the ~8% of orders in the last 30 days). That hash build is faster, but the dominant cost — reading 250,000 order_item rows — did not change. Adding `idx_order_item_variant` made things worse (regression to ~95 ms) because a hash join with a full Seq Scan on order_item is cheaper than a nested loop with index lookups when most of the table must be visited.

**Q4 did not improve.** The query aggregates 85,072 successful payments out of 89,331 total — about 95% of the table. At that selectivity, a sequential scan is always cheaper than an index scan, because the overhead of following index pointers to random heap pages exceeds the cost of reading the pages sequentially. The partial index `idx_payment_success_paid_at` was ignored by the planner on every run. The sort spill to disk (external merge, 2,248 kB) is a separate issue: raising `work_mem` to 64 MB in a session eliminated the spill (sort switched to quicksort in memory, 6,383 kB), but execution time stayed at ~98 ms because the sequential scan is the bottleneck, not the sort. The work_mem experiment is in `evidence/work-mem-experiment.txt`.

**Q1 and Q6 did not benefit from most indexes.** Q1 was already fast (1.71 ms baseline) because product_variant has only 5,000 rows and product has 1,000 rows. The planner preferred sequential scans on those small tables even when indexes existed. The partial index `idx_variant_instock` was an exception: it pre-filters to rows where `stock_qty > 0 AND deleted_at IS NULL`, shrinking the scan from 5,000 rows to 198 (a 96% reduction), and the 10-run re-test confirmed a consistent 47% improvement (2.62 ms → 1.39 ms). Q6 scans review (10,000 rows, ~114 pages) and product (1,000 rows, ~15 pages). Both tables fit in a few hundred buffer reads; an index scan adds per-row overhead that outweighs the benefit. The `idx_review_product` index regressed Q6 from 9.13 ms to 13.02 ms on the median.

**Index storage cost.** The four kept indexes add 5,696 kB total: `idx_orders_customer_date` 3,104 kB, `idx_orders_order_date` 2,208 kB, `idx_orders_awaiting` 328 kB, `idx_variant_instock` 56 kB. The three orders indexes together (5,640 kB) are about 38% of the orders table size (15 MB). Every INSERT or UPDATE to indexed columns must also update the index, so write throughput on orders and product_variant is lower with these indexes in place. This was not measured in this portfolio.

---

## g. Limitations

Timings were measured on a single machine under low concurrency. Results vary between runs: Q1 ranged from 0.90 ms to 1.90 ms across the 10-run re-test, and Q6 varied from 7.92 ms to 19.49 ms across the baseline runs. The medians are a reasonable central estimate but are not stable benchmarks.

The data is synthetic. All products, customers and orders were generated by a single bulk script. Real ThreadHaus data would have different distributions — for example, popular sizes and colours would appear far more often than rare ones, which might change the planner's choice of index vs Seq Scan on product_variant. The review deduplication capped at 10,000 rows rather than the intended 20,000 because the seed formula had limited range.

I did not test write performance (the cost of INSERT and UPDATE with indexes in place), concurrent query behaviour, or the effect of autovacuum and table bloat on plan choices.


---

## h. How to Reproduce

```bash
# 1. Create the database (connect as a role with CREATEDB)
psql -d postgres -c "DROP DATABASE IF EXISTS threadhaus_perf;"
psql -d postgres -c "CREATE DATABASE threadhaus_perf;"

# 2. Load the schema
psql -v ON_ERROR_STOP=1 -d threadhaus_perf -f ../portfolio-1-database-design/schema.sql

# 3. Load bulk data (takes about 23 seconds)
psql -v ON_ERROR_STOP=1 -d threadhaus_perf -f bulk-data.sql

# 4. Verify row counts
psql -v ON_ERROR_STOP=1 -d threadhaus_perf -f verify-bulk-data.sql

# 5. Run baseline queries
psql -d threadhaus_perf -f queries.sql

# 6. Get a baseline plan for one query (example: Q2)
psql -d threadhaus_perf -c "EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_id, o.order_date, o.status, o.total_amount,
       COUNT(oi.order_item_id), SUM(oi.quantity * oi.unit_price)
FROM orders o JOIN order_item oi ON oi.order_id = o.order_id
WHERE o.customer_id = 4790
GROUP BY o.order_id, o.order_date, o.status, o.total_amount
ORDER BY o.order_date DESC;"

# 7. Apply indexes
psql -d threadhaus_perf -f indexes.sql

# 8. Re-run the same plan to see the difference
psql -d threadhaus_perf -c "EXPLAIN (ANALYZE, BUFFERS) ..."

# 9. Undo all indexes
psql -d threadhaus_perf -f drop-indexes.sql
```

All commands use plain `psql` with `PGHOST`, `PGUSER`, and `PGDATABASE` set in the environment. No sudo required.

---

## i. Files and Evidence

**Scripts:**

| File | What it is |
|---|---|
| `bulk-data.sql` | Generates all test data in SQL. Needs a fresh database with schema loaded. |
| `verify-bulk-data.sql` | Row counts, total_amount check, status distribution. |
| `queries.sql` | Six baseline queries Q1–Q6. |
| `indexes.sql` | All indexes tested. Dropped ones kept as comments with reasons. |
| `drop-indexes.sql` | Drops all four kept indexes to restore the baseline. |

**Evidence files:**

| File | What it shows |
|---|---|
| `evidence/bulk-load-run.txt` | Timing output of loading bulk-data.sql (~23 seconds total) |
| `evidence/verify-output.txt` | Row counts and verification query results |
| `evidence/baseline-indexes.txt` | The 25 automatic indexes before any manual index was added |
| `evidence/baseline-results.txt` | Actual query output for Q1–Q6 |
| `evidence/baseline-plans.txt` | EXPLAIN (ANALYZE, BUFFERS) plans before indexing |
| `evidence/baseline-timings.md` | Baseline median timings and scan types |
| `evidence/q1-retest.txt` | 10-run re-test for Q1 confirming idx_variant_instock is beneficial |
| `evidence/after-plans.txt` | Plans after indexing for all six queries |
| `evidence/after-timings.md` | Before/after timing table with final index decisions |
| `evidence/index-sizes.txt` | Size of each kept index and the five largest tables |
| `evidence/work-mem-experiment.txt` | Q4 with work_mem = 64MB: disk spill removed, time unchanged |
| `evidence/after-indexes.txt` | Final \di output showing all 29 indexes |

---

## j. AI Use

I used an AI assistant in this portfolio. The full log of what i used it for is in `AI-USE.md` in the repo root.

---

## h. How to Reproduce

```bash
# 1. Create the database (connect as a role with CREATEDB)
psql -d postgres -c "DROP DATABASE IF EXISTS threadhaus_perf;"
psql -d postgres -c "CREATE DATABASE threadhaus_perf;"

# 2. Load the schema
psql -v ON_ERROR_STOP=1 -d threadhaus_perf -f ../portfolio-1-database-design/schema.sql

# 3. Load bulk data (takes about 23 seconds)
psql -v ON_ERROR_STOP=1 -d threadhaus_perf -f bulk-data.sql

# 4. Verify row counts
psql -v ON_ERROR_STOP=1 -d threadhaus_perf -f verify-bulk-data.sql

# 5. Run baseline queries
psql -d threadhaus_perf -f queries.sql

# 6. Get a baseline plan for one query (example: Q2)
psql -d threadhaus_perf -c "EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_id, o.order_date, o.status, o.total_amount,
       COUNT(oi.order_item_id), SUM(oi.quantity * oi.unit_price)
FROM orders o JOIN order_item oi ON oi.order_id = o.order_id
WHERE o.customer_id = 4790
GROUP BY o.order_id, o.order_date, o.status, o.total_amount
ORDER BY o.order_date DESC;"

# 7. Apply indexes
psql -d threadhaus_perf -f indexes.sql

# 8. Re-run the same plan to see the difference
# (paste the EXPLAIN query above again)

# 9. Undo all indexes
psql -d threadhaus_perf -f drop-indexes.sql
```

All commands use plain `psql` with `PGHOST`, `PGUSER`, and `PGDATABASE` set in the environment. No sudo required.

---

## i. Files and Evidence

**Scripts:**

| File | What it is |
|---|---|
| `bulk-data.sql` | Generates all test data in SQL. Needs a fresh database with schema loaded. |
| `verify-bulk-data.sql` | Row counts, total_amount check, status distribution. |
| `queries.sql` | Six baseline queries Q1–Q6. |
| `indexes.sql` | All indexes tested. Dropped ones kept as comments with reasons. |
| `drop-indexes.sql` | Drops all four kept indexes to restore the baseline. |

**Evidence files:**

| File | What it shows |
|---|---|
| `evidence/bulk-load-run.txt` | Timing output of loading bulk-data.sql (~23 seconds total) |
| `evidence/verify-output.txt` | Row counts and verification query results |
| `evidence/baseline-indexes.txt` | The 25 automatic indexes before any manual index was added |
| `evidence/baseline-results.txt` | Actual query output for Q1–Q6 |
| `evidence/baseline-plans.txt` | EXPLAIN (ANALYZE, BUFFERS) plans before indexing |
| `evidence/baseline-timings.md` | Baseline median timings and scan types |
| `evidence/q1-retest.txt` | 10-run re-test for Q1 confirming idx_variant_instock is beneficial |
| `evidence/after-plans.txt` | Plans after indexing for all six queries |
| `evidence/after-timings.md` | Before/after timing table with final index decisions |
| `evidence/index-sizes.txt` | Size of each kept index and the five largest tables |
| `evidence/work-mem-experiment.txt` | Q4 with work_mem = 64MB: disk spill removed, time unchanged |
| `evidence/after-indexes.txt` | Final \di output showing all 29 indexes |

---

## j. AI Use

I used an AI assistant throughout this portfolio. The full log of what it did and what I checked or changed is in `AI-USE.md` in the repo root.
