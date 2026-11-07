-- 05-deadlock-session2.sql
-- Deadlock scenario: Session 2 locks variant 6 first, then tries variant 3.
-- Opposite order from S1 → circular wait → deadlock.

SELECT pg_sleep(0.5);

SELECT '[S2] ' || clock_timestamp()::text || ' BEGIN' AS log;
BEGIN;

SELECT '[S2] ' || clock_timestamp()::text || ' Locking variant 6 (FOR UPDATE)' AS log;
SELECT variant_id, stock_qty FROM product_variant WHERE variant_id = 6 FOR UPDATE;

SELECT '[S2] ' || clock_timestamp()::text || ' Sleeping 1s — S1 will try to lock variant 6 during this sleep' AS log;
SELECT pg_sleep(1);

SELECT '[S2] ' || clock_timestamp()::text || ' Now trying to lock variant 3 (will deadlock with S1)' AS log;
SELECT variant_id, stock_qty FROM product_variant WHERE variant_id = 3 FOR UPDATE;

-- If we reach here, S2 was not the deadlock victim
SELECT '[S2] ' || clock_timestamp()::text || ' Got both locks. Placing order.' AS log;

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
