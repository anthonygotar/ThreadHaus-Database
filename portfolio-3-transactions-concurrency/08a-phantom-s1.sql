-- 08a-phantom-s1.sql
-- Session 1 under READ COMMITTED.
-- Counts orders for customer 1 twice with a 2s sleep between.
-- S2 inserts a new order for customer 1 during the sleep.
-- Under READ COMMITTED the second count is higher — phantom read.

SELECT '[S1] ' || clock_timestamp()::text || ' BEGIN READ COMMITTED' AS log;
BEGIN ISOLATION LEVEL READ COMMITTED;

SELECT '[S1] ' || clock_timestamp()::text || ' First count of orders for customer 1' AS log;
SELECT COUNT(*) AS order_count FROM orders WHERE customer_id = 1;

SELECT '[S1] ' || clock_timestamp()::text || ' Sleeping 2s (S2 inserts new order during sleep)' AS log;
SELECT pg_sleep(2);

SELECT '[S1] ' || clock_timestamp()::text || ' Second count — READ COMMITTED sees S2 new row (phantom)' AS log;
SELECT COUNT(*) AS order_count FROM orders WHERE customer_id = 1;

COMMIT;
SELECT '[S1] Done.' AS log;
