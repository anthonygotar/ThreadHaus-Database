-- 04a-oversell-session1.sql
-- Fix A: SELECT ... FOR UPDATE prevents the lost update.
-- Session 1 acquires a row lock on variant 3 immediately.

SELECT '[S1] ' || clock_timestamp()::text || ' BEGIN' AS log;
BEGIN;

SELECT '[S1] ' || clock_timestamp()::text || ' SELECT FOR UPDATE (acquires row lock)' AS log;
SELECT stock_qty FROM product_variant WHERE variant_id = 3 FOR UPDATE;

-- Simulate checkout delay — S2 will block on its SELECT FOR UPDATE during this sleep
SELECT pg_sleep(2);
SELECT '[S1] ' || clock_timestamp()::text || ' Woke up. stock=1, placing order.' AS log;

UPDATE product_variant SET stock_qty = stock_qty - 1 WHERE variant_id = 3;

INSERT INTO orders (customer_id, address_id, status, total_amount)
VALUES (1, 1, 'paid', 6500.00)
RETURNING order_id \gset

INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
VALUES (:order_id, 3, 1, 6500.00);

SELECT '[S1] ' || clock_timestamp()::text || ' COMMIT (releasing lock)' AS log;
COMMIT;
SELECT '[S1] Done.' AS log;
