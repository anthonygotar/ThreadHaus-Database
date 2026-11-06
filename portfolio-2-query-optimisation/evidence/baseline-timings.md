# Baseline query timings — threadhaus_perf, no manual indexes

Three runs of EXPLAIN (ANALYZE, BUFFERS) per query. Median execution time recorded.

| Query | Business question | Scan types | Key tables / rows scanned | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Median (ms) |
|---|---|---|---|---|---|---|---|
| Q1 | Catalogue search: in-stock Men variants size M colour Black | Seq Scan on product_variant (5000 rows), Seq Scan on product (1000 rows), Seq Scan on category (12 rows); Hash Join | product_variant: 5000 scanned, 198 passed filter; product: 1000; category: 12 | 1.59 | 1.71 | 2.17 | **1.71** |
| Q2 | Order history for customer 4790 | Seq Scan on orders (100000 rows); Index Scan on order_item via order_item_order_id_variant_id_key | orders: 100000 scanned, 10 matched; order_item: index lookup 10 times | 10.50 | 18.02 | 16.89 | **16.89** |
| Q3 | Best sellers last 30 days excl. cancelled | Seq Scan on order_item (250000 rows), Seq Scan on orders (100000 rows), Seq Scan on product_variant (5000), Seq Scan on product (1000); Hash Join x3; HashAggregate | order_item: 250000; orders: 100000 scanned, 7750 passed filter | 106.98 | 112.24 | 114.75 | **112.24** |
| Q4 | Monthly revenue from successful payments | Seq Scan on payment (89331 rows); Sort (external merge, spills to disk 2248 kB); GroupAggregate | payment: 89331 scanned, 85072 matched | 99.30 | 93.64 | 98.01 | **98.01** |
| Q5 | Orders paid/processing with no delivery | Parallel Seq Scan on orders (100000 rows); Index Only Scan on delivery via delivery_order_id_key; Nested Loop Anti Join | orders: 100000 scanned, 14003 matched; delivery: index only scan | 19.12 | 20.85 | 24.84 | **20.85** |
| Q6 | Top 20 products by avg rating (min 5 reviews) | Seq Scan on review (10000 rows), Seq Scan on product (1000 rows); Hash Join; HashAggregate | review: 10000; product: 1000 | 7.92 | 19.49 | 9.13 | **9.13** |

## Notes
- Q3 and Q4 are the slowest. Both do full sequential scans of large tables (250k order_items, 100k orders, 89k payments).
- Q4 spills sort to disk (external merge, 2248 kB). No `work_mem` increase applied at this stage.
- Q2 does a full Seq Scan on orders (100k rows) to find 10 rows for one customer. The composite UNIQUE index on order_item is used for the lookup half, but orders has no index on customer_id.
- Q5 uses a Parallel Seq Scan (1 worker) on orders and an Index Only Scan on delivery. The anti-join is efficient but the orders scan is still full.
- Q1 and Q6 are fast because the tables involved are small (1k products, 5k variants, 10k reviews).
- No interpretation or optimisation done at this stage. Plans recorded as-is for comparison in step 8.
