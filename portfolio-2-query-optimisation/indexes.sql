-- ThreadHaus indexes for query optimisation
-- Portfolio 2: Query Optimisation
-- Each index is added in the order it was tested.
-- Dropped indexes are noted with a comment showing the reason.

-- a. Q2: order history by customer
-- Baseline median: 16.89 ms. After: 0.80 ms (-95%). Bitmap Index Scan used.
CREATE INDEX idx_orders_customer_date ON orders (customer_id, order_date DESC);

