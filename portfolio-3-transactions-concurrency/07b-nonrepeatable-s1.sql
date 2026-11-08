-- 07b-nonrepeatable-s1.sql
-- Session 1 under REPEATABLE READ.
-- The snapshot is taken at the first statement of the transaction.
-- Second read returns the same price as the first (snapshot isolation).
-- After the second read, S1 tries to UPDATE the same row — PostgreSQL
-- detects that S2 has committed a change and raises:
--   ERROR: could not serialize access due to concurrent update

SELECT '[S1] ' || clock_timestamp()::text || ' BEGIN REPEATABLE READ' AS log;
BEGIN ISOLATION LEVEL REPEATABLE READ;

SELECT '[S1] ' || clock_timestamp()::text || ' First read of variant 3 price' AS log;
SELECT variant_id, sku, price FROM product_variant WHERE variant_id = 3;

SELECT '[S1] ' || clock_timestamp()::text || ' Sleeping 2s (S2 updates price during sleep)' AS log;
SELECT pg_sleep(2);

SELECT '[S1] ' || clock_timestamp()::text || ' Second read — REPEATABLE READ sees original snapshot value' AS log;
SELECT variant_id, sku, price FROM product_variant WHERE variant_id = 3;

SELECT '[S1] ' || clock_timestamp()::text || ' Trying to UPDATE price — expect serialization error' AS log;
UPDATE product_variant SET price = price + 100 WHERE variant_id = 3;

COMMIT;
SELECT '[S1] Done.' AS log;
