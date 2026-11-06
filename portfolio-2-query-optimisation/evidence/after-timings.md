# After-indexing query timings — threadhaus_perf

5 runs after each index. Median recorded. Baseline medians from baseline-timings.md.

| Query | Baseline median (ms) | After median (ms) | Change % | Scan before | Scan after | Index used |
|---|---|---|---|---|---|---|
| Q1 Catalogue search | 1.71 | 1.93 | +13% (within noise) | Seq Scan on product_variant (5000 rows) | Bitmap Index Scan on idx_variant_instock (198 rows) | idx_variant_instock ✓ |
| Q2 Order history | 16.89 | 0.80 | **-95%** | Seq Scan on orders (100k rows) | Bitmap Index Scan on idx_orders_customer_date (10 rows) | idx_orders_customer_date ✓ |
| Q3 Best sellers | 112.24 | 90.11 | **-20%** | Seq Scan on orders (100k rows) | Bitmap Index Scan on idx_orders_order_date (~7.7k rows) | idx_orders_order_date ✓ |
| Q4 Monthly sales | 98.01 | 98.01 | 0% | Seq Scan on payment + external merge (disk) | Unchanged — no index kept | none |
| Q5 Awaiting rider | 20.85 | 0.73 | **-97%** | Parallel Seq Scan on orders (100k rows) | Index Scan on idx_orders_awaiting (14k rows) | idx_orders_awaiting ✓ |
| Q6 Product ratings | 9.13 | 9.13 | 0% | Seq Scan on review (10k rows) | Unchanged — no index kept | none |

## Notes
- Q1: index IS used but timing gain is within measurement noise (query was already fast, <2ms).
- Q2: biggest win. Single-column scan of 100k orders replaced by targeted bitmap index lookup.
- Q3: moderate win. order_item still seq-scanned (250k rows, hash join is cheaper than index here). Only the orders filter side benefited.
- Q4: no index helped. Query must read ~95% of payment table — seq scan beats index scan at that selectivity. See work_mem experiment.
- Q5: best proportional win. Partial index covers exactly the rows needed; planner switched immediately from Parallel Seq Scan to Index Scan.
- Q6: review table (10k rows, 114 pages) is too small for an index to help. Seq scan is faster.
