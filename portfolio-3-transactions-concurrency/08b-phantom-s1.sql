-- 08b-phantom-s1.sql
-- Session 1 under REPEATABLE READ.
-- PostgreSQL uses snapshot isolation — the snapshot is taken at first statement.
-- The second count returns the same value even after S2 inserts a new order.
-- PostgreSQL's REPEATABLE READ prevents phantom reads (unlike the SQL standard).

SELECT '[S1] ' || clock_timestamp()::text || ' BEGIN REPEATABLE READ' AS log;
BEGIN ISOLATION LEVEL REPEATABLE READ;

SELECT '[S1] ' || clock_timestamp()::text || ' First count of orders for customer 1' AS log;
SELECT COUNT(*) AS order_count FROM orders WHERE customer_id = 1;

SELECT '[S1] ' || clock_timestamp()::text || ' Sleeping 2s (S2 inserts new order during sleep)' AS log;
SELECT pg_sleep(2);

SELECT '[S1] ' || clock_timestamp()::text || ' Second count — REPEATABLE READ snapshot unchanged (no phantom)' AS log;
SELECT COUNT(*) AS order_count FROM orders WHERE customer_id = 1;

COMMIT;
SELECT '[S1] Done.' AS log;
