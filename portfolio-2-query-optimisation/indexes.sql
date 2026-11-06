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

