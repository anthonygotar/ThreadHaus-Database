-- 03-oversell-session1.sql
-- Session 1: buyer 1 (customer 1, address 1) wants variant 3 (Slim Joggers M Black).
-- Uses READ COMMITTED (default). Reads stock, sleeps, then writes the value it computed.
-- This demonstrates a lost update / oversell race condition.

SELECT '[S1] ' || clock_timestamp()::text || ' BEGIN' AS log;
BEGIN;

SELECT '[S1] ' || clock_timestamp()::text || ' SELECT stock_qty (should be 1)' AS log;
SELECT stock_qty FROM product_variant WHERE variant_id = 3;

-- Simulate checkout delay — S2 runs its SELECT during this sleep
SELECT pg_sleep(2);
SELECT '[S1] ' || clock_timestamp()::text || ' Woke up. Writing stock = 0 (read was 1, buying 1)' AS log;

-- Write back the value we computed: stock - 1 = 0
UPDATE product_variant SET stock_qty = 0 WHERE variant_id = 3;

INSERT INTO orders (customer_id, address_id, status, total_amount)
VALUES (1, 1, 'paid', 6500.00)
RETURNING order_id \gset

INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
VALUES (:order_id, 3, 1, 6500.00);

SELECT '[S1] ' || clock_timestamp()::text || ' COMMIT' AS log;
COMMIT;
SELECT '[S1] Done.' AS log;
