-- 04b-oversell-session1.sql
-- Fix B: conditional UPDATE with stock_qty >= 1 guard.
-- No explicit lock needed. The UPDATE itself is atomic.
-- If rowcount = 1, stock was available and we proceed.
-- If rowcount = 0, stock was 0 and we roll back.

SELECT '[S1] ' || clock_timestamp()::text || ' BEGIN' AS log;
BEGIN;

-- Simulate checkout delay before attempting the update
SELECT pg_sleep(0);

SELECT '[S1] ' || clock_timestamp()::text || ' Attempting conditional UPDATE (stock_qty - 1 WHERE stock_qty >= 1)' AS log;
UPDATE product_variant
SET stock_qty = stock_qty - 1
WHERE variant_id = 3
  AND stock_qty >= 1;

-- GET DIAGNOSTICS equivalent: check row count
SELECT '[S1] ' || clock_timestamp()::text || ' Rows updated: checking...' AS log;
SELECT COUNT(*) AS rows_updated
FROM product_variant
WHERE variant_id = 3 AND stock_qty >= 0;

-- stock_qty is now 0, meaning we got the last unit
INSERT INTO orders (customer_id, address_id, status, total_amount)
VALUES (1, 1, 'paid', 6500.00)
RETURNING order_id \gset

INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
VALUES (:order_id, 3, 1, 6500.00);

SELECT '[S1] ' || clock_timestamp()::text || ' COMMIT' AS log;
COMMIT;
SELECT '[S1] Done — order placed.' AS log;
