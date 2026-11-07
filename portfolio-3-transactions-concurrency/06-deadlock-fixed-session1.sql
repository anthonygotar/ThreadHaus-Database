-- 06-deadlock-fixed-session1.sql
-- Deadlock fix: both sessions lock variants in ascending variant_id order.
-- S1 locks variant 3 then 6 (ascending). S2 does the same.
-- S2 will wait for S1's lock on variant 3 — no cycle, no deadlock.

SELECT '[S1] ' || clock_timestamp()::text || ' BEGIN' AS log;
BEGIN;

-- Lock both variants together in ascending order in a single statement
SELECT '[S1] ' || clock_timestamp()::text || ' Locking variants 3 and 6 in ascending order' AS log;
SELECT variant_id, stock_qty
FROM product_variant
WHERE variant_id IN (3, 6)
ORDER BY variant_id
FOR UPDATE;

SELECT '[S1] ' || clock_timestamp()::text || ' Sleeping 2s while holding both locks' AS log;
SELECT pg_sleep(2);

SELECT '[S1] ' || clock_timestamp()::text || ' Placing order for variants 3 and 6' AS log;

UPDATE product_variant SET stock_qty = stock_qty - 1 WHERE variant_id = 3;
UPDATE product_variant SET stock_qty = stock_qty - 1 WHERE variant_id = 6;

INSERT INTO orders (customer_id, address_id, status, total_amount)
VALUES (1, 1, 'paid', 43000.00)
RETURNING order_id \gset

INSERT INTO order_item (order_id, variant_id, quantity, unit_price) VALUES (:order_id, 3, 1, 6500.00);
INSERT INTO order_item (order_id, variant_id, quantity, unit_price) VALUES (:order_id, 6, 1, 36500.00);

SELECT '[S1] ' || clock_timestamp()::text || ' COMMIT' AS log;
COMMIT;
SELECT '[S1] Done — order committed.' AS log;
