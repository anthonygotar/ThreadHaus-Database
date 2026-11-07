-- 06-deadlock-fixed-session2.sql
-- Deadlock fix: Session 2 also locks in ascending variant_id order.
-- Both sessions request the same lock order: variant 3 first, then 6.
-- S2 will block waiting for S1's lock on variant 3 — no cycle, no deadlock.

SELECT pg_sleep(0.5);

SELECT '[S2] ' || clock_timestamp()::text || ' BEGIN' AS log;
BEGIN;

SELECT '[S2] ' || clock_timestamp()::text || ' Trying to lock variants 3 and 6 (will wait for S1 to release)' AS log;
SELECT variant_id, stock_qty
FROM product_variant
WHERE variant_id IN (3, 6)
ORDER BY variant_id
FOR UPDATE;

SELECT '[S2] ' || clock_timestamp()::text || ' Lock acquired — S1 has committed. Placing order.' AS log;

UPDATE product_variant SET stock_qty = stock_qty - 1 WHERE variant_id = 3;
UPDATE product_variant SET stock_qty = stock_qty - 1 WHERE variant_id = 6;

INSERT INTO orders (customer_id, address_id, status, total_amount)
VALUES (2, 2, 'paid', 43000.00)
RETURNING order_id \gset

INSERT INTO order_item (order_id, variant_id, quantity, unit_price) VALUES (:order_id, 3, 1, 6500.00);
INSERT INTO order_item (order_id, variant_id, quantity, unit_price) VALUES (:order_id, 6, 1, 36500.00);

SELECT '[S2] ' || clock_timestamp()::text || ' COMMIT' AS log;
COMMIT;
SELECT '[S2] Done — order committed.' AS log;
