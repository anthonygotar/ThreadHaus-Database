-- 03-oversell-session2.sql
-- Session 2: buyer 2 (customer 2, address 2) wants variant 3 (Slim Joggers M Black).
-- Starts 1 second after session 1 so it reads stock before S1 commits.

-- Small initial sleep so S1 starts first and completes its SELECT
SELECT pg_sleep(1);

SELECT '[S2] ' || clock_timestamp()::text || ' BEGIN' AS log;
BEGIN;

SELECT '[S2] ' || clock_timestamp()::text || ' SELECT stock_qty (will also see 1 — S1 has not committed yet)' AS log;
SELECT stock_qty FROM product_variant WHERE variant_id = 3;

-- Simulate checkout delay — S1 commits during this sleep
SELECT pg_sleep(2);
SELECT '[S2] ' || clock_timestamp()::text || ' Woke up. Writing stock = 0 (read was 1, buying 1)' AS log;

-- Write back the value we computed: stock - 1 = 0
-- This overwrites S1 committed write — lost update!
UPDATE product_variant SET stock_qty = 0 WHERE variant_id = 3;

INSERT INTO orders (customer_id, address_id, status, total_amount)
VALUES (2, 2, 'paid', 6500.00)
RETURNING order_id \gset

INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
VALUES (:order_id, 3, 1, 6500.00);

SELECT '[S2] ' || clock_timestamp()::text || ' COMMIT' AS log;
COMMIT;
SELECT '[S2] Done.' AS log;
