-- 04b-oversell-session2.sql
-- Fix B: Session 2 also uses the conditional UPDATE.
-- It starts 1s after S1. By the time it runs, S1 has committed stock=0.
-- The WHERE stock_qty >= 1 condition matches 0 rows, so no update happens.
-- Application sees 0 rows affected and rolls back.

SELECT pg_sleep(1);

SELECT '[S2] ' || clock_timestamp()::text || ' BEGIN' AS log;
BEGIN;

SELECT '[S2] ' || clock_timestamp()::text || ' Attempting conditional UPDATE (stock_qty - 1 WHERE stock_qty >= 1)' AS log;
UPDATE product_variant
SET stock_qty = stock_qty - 1
WHERE variant_id = 3
  AND stock_qty >= 1;

-- Check whether the update matched any row
SELECT '[S2] ' || clock_timestamp()::text || ' Checking stock after update attempt' AS log;
SELECT stock_qty FROM product_variant WHERE variant_id = 3;

-- stock_qty is still 0 — the UPDATE matched 0 rows, meaning out of stock
SELECT '[S2] ' || clock_timestamp()::text || ' UPDATE matched 0 rows — out of stock. Rolling back.' AS log;
ROLLBACK;
SELECT '[S2] Done — no order placed.' AS log;
