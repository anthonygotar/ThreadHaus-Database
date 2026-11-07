-- 04a-oversell-session2.sql
-- Fix A: Session 2 also uses SELECT ... FOR UPDATE.
-- It blocks while S1 holds the lock, then re-reads stock = 0 and rolls back.

SELECT pg_sleep(1);

SELECT '[S2] ' || clock_timestamp()::text || ' BEGIN' AS log;
BEGIN;

SELECT '[S2] ' || clock_timestamp()::text || ' SELECT FOR UPDATE (will block until S1 commits)' AS log;
-- This blocks here until S1 releases its lock
SELECT stock_qty FROM product_variant WHERE variant_id = 3 FOR UPDATE;

SELECT '[S2] ' || clock_timestamp()::text || ' Lock acquired. Reading stock now.' AS log;
SELECT stock_qty FROM product_variant WHERE variant_id = 3;

-- After S1 committed, stock is 0. S2 sees this and rolls back.
SELECT '[S2] ' || clock_timestamp()::text || ' Stock is 0. Rolling back — cannot place order.' AS log;
ROLLBACK;
SELECT '[S2] Done — no order placed.' AS log;
