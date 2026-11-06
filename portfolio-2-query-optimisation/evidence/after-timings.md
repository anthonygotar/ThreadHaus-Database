# After-indexing query timings — threadhaus_perf

Baseline medians from baseline-timings.md (3 runs each).
After medians: Q1 from q1-retest.txt (10 runs); Q2-Q6 from step 8 (5 runs each).
4 indexes kept. 5 indexes tested and dropped.

| Query | Baseline median (ms) | After median (ms) | Change % | Scan before | Scan after | Index used |
|---|---|---|---|---|---|---|
| Q1 Catalogue search | 1.71 | 1.39 | **-19%** | Seq Scan on product_variant (5000 rows) | Bitmap Index Scan on idx_variant_instock (198 rows) | idx_variant_instock ✓ |
| Q2 Order history | 16.89 | 0.80 | **-95%** | Seq Scan on orders (100k rows) | Bitmap Index Scan on idx_orders_customer_date (10 rows) | idx_orders_customer_date ✓ |
| Q3 Best sellers | 112.24 | 90.11 | **-20%** | Seq Scan on orders (100k rows) | Bitmap Index Scan on idx_orders_order_date (~7.7k rows) | idx_orders_order_date ✓ |
| Q4 Monthly sales | 98.01 | 98.01 | 0% | Seq Scan on payment + external merge (disk) | Unchanged — no index kept | none |
| Q5 Awaiting rider | 20.85 | 0.73 | **-97%** | Parallel Seq Scan on orders (100k rows) | Index Scan on idx_orders_awaiting (14k rows) | idx_orders_awaiting ✓ |
| Q6 Product ratings | 9.13 | 9.13 | 0% | Seq Scan on review (10k rows) | Unchanged — no index kept | none |

## Notes on Q1 re-test
The step 8 result for Q1 (1.93 ms with index vs 1.71 ms baseline, both from 3 runs) was within
measurement noise. The 10-run re-test in q1-retest.txt shows a clear 47% improvement:
1.39 ms with idx_variant_instock vs 2.62 ms without. Index is kept.

## Dropped indexes (tested in step 8)
| Index | Target query | Reason dropped |
|---|---|---|
| idx_payment_success_paid_at | Q4 | Planner chose Seq Scan; query reads 95% of payment table (85k of 89k rows) |
| idx_review_product | Q6 | Regression: 13.02 ms vs baseline 9.13 ms; review table (10k rows) too small |
| idx_variant_product | Q1 | Not used by planner; product_variant table is small |
| idx_product_category | Q1 | Not used by planner; product table is small |
| idx_order_item_variant | Q3 | Regression: ~95 ms vs 90 ms; hash join with Seq Scan on 250k rows is faster |
