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

