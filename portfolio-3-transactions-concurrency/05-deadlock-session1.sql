-- 05-deadlock-session1.sql
-- Deadlock scenario: Session 1 locks variant 3 first, then tries variant 6.
-- Session 2 locks variant 6 first, then tries variant 3.
-- Circular wait → PostgreSQL detects deadlock and aborts one session.

SELECT '[S1] ' || clock_timestamp()::text || ' BEGIN' AS log;
BEGIN;

SELECT '[S1] ' || clock_timestamp()::text || ' Locking variant 3 (FOR UPDATE)' AS log;
SELECT variant_id, stock_qty FROM product_variant WHERE variant_id = 3 FOR UPDATE;

SELECT '[S1] ' || clock_timestamp()::text || ' Sleeping 1s — S2 will lock variant 6 during this sleep' AS log;
SELECT pg_sleep(1);

SELECT '[S1] ' || clock_timestamp()::text || ' Now trying to lock variant 6 (will deadlock with S2)' AS log;
SELECT variant_id, stock_qty FROM product_variant WHERE variant_id = 6 FOR UPDATE;

-- If we reach here, S1 was not the deadlock victim
SELECT '[S1] ' || clock_timestamp()::text || ' Got both locks. Placing order.' AS log;

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
