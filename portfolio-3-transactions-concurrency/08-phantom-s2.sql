-- 08-phantom-s2.sql
-- Session 2: starts 1s after S1, inserts a new order for customer 1 and commits.

SELECT pg_sleep(1);

SELECT '[S2] ' || clock_timestamp()::text || ' BEGIN' AS log;
BEGIN;

SELECT '[S2] ' || clock_timestamp()::text || ' Inserting new order for customer 1' AS log;
INSERT INTO orders (customer_id, address_id, status, total_amount)
VALUES (1, 1, 'pending', 5000.00);

SELECT '[S2] ' || clock_timestamp()::text || ' COMMIT' AS log;
COMMIT;
SELECT '[S2] Done — new order committed.' AS log;
