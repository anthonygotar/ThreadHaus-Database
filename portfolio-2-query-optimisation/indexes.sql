-- ThreadHaus indexes for query optimisation
-- Portfolio 2: Query Optimisation
-- Each index is added in the order it was tested.
-- Dropped indexes are noted with a comment showing the reason.

-- a. Q2: order history by customer
-- Baseline median: 16.89 ms. After: 0.80 ms (-95%). Bitmap Index Scan used.
CREATE INDEX idx_orders_customer_date ON orders (customer_id, order_date DESC);

-- b. Q3: best sellers – filter orders by date range
-- Baseline median: 112.24 ms. After: 90.11 ms (-20%). Bitmap Index Scan on orders used.
CREATE INDEX idx_orders_order_date ON orders (order_date);

-- c. Q5: orders awaiting rider – partial index on status filter
-- Baseline median: 20.85 ms. After: 0.73 ms (-97%). Index Scan used.
CREATE INDEX idx_orders_awaiting ON orders (order_date) WHERE status IN ('paid', 'processing');

-- d. Q4: monthly sales report – partial index on payment(paid_at) INCLUDE (amount)
-- TESTED AND DROPPED. Planner chose Seq Scan over this index on every run.
-- Median stayed at 99.62 ms vs baseline 98.01 ms — no gain, slight regression.
-- Reason: Q4 reads ~95% of the payment table (85k of 89k rows). A full scan is
-- cheaper than an index scan when selectivity is that low.
-- DROP INDEX idx_payment_success_paid_at;

-- e. Q6: product ratings – index on review(product_id) INCLUDE (rating)
-- TESTED AND DROPPED. Planner chose Seq Scan on review in every run.
-- Median 13.02 ms vs baseline 9.13 ms — actually slower.
-- Reason: review table is small (10k rows, 114 pages). Sequential scan is faster
-- than an index scan when the whole table fits in a few buffer reads.
-- DROP INDEX idx_review_product;

-- f. Q1: catalogue search – three indexes tested together
-- idx_variant_instock KEPT. Used via Bitmap Index Scan. Baseline 1.71 ms, after 1.93 ms —
--   within noise on a fast query, but index IS used and reduces scanned rows from 5000 to 198.
-- idx_variant_product TESTED AND DROPPED. Not used by planner (product_variant is small).
-- idx_product_category TESTED AND DROPPED. Not used by planner (product table is small).
CREATE INDEX idx_variant_instock ON product_variant (size, colour) WHERE stock_qty > 0 AND deleted_at IS NULL;
-- DROP INDEX idx_variant_product;
-- DROP INDEX idx_product_category;

