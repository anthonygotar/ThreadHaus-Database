-- 02-order-rollback.sql
-- ThreadHaus Portfolio 3: Transactions and Concurrency
-- Three rollback scenarios demonstrating transaction behaviour.
--
-- Run reset-db.sh before this file so all IDs and stock values are known.
--
-- IDs (fresh database):
--   customer_id 4 = Seun Ogundimu, address_id 5
--   variant 3  = Slim Joggers M Black,    price 6500, stock 30
--   variant 6  = Agbada Set XXL Navy,     price 36500, stock 5
--   variant 8  = Ankara Blouse M Yellow,  price 8000,  stock 22

-- =============================================================================
-- SCENARIO A: Automatic abort due to CHECK constraint violation
-- The transaction tries to reduce variant 6 stock by 10, but stock is only 5.
-- The UPDATE violates CHECK (stock_qty >= 0) and PostgreSQL aborts the
-- transaction automatically. Any further command in the same session is
-- rejected until ROLLBACK is issued.
-- =============================================================================

\echo ''
\echo '========== SCENARIO A: Automatic abort (CHECK violation) =========='
\echo ''

\echo '--- Stock BEFORE scenario A ---'
SELECT variant_id, sku, stock_qty FROM product_variant WHERE variant_id IN (3, 6);

BEGIN;

  -- Insert the order
  INSERT INTO orders (customer_id, address_id, status, total_amount)
  VALUES (4, 5, 'pending', 0.00)
  RETURNING order_id \gset

  \echo '--- Order inserted: order_id :order_id ---'

  -- Item 1: variant 3, qty 2 — this succeeds and reduces stock
  INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
  VALUES (:order_id, 3, 2, 6500.00);

  UPDATE product_variant SET stock_qty = stock_qty - 2 WHERE variant_id = 3;
  \echo '--- Item 1 stock reduced (variant 3 stock should now be 28) ---'

  -- Item 2: variant 6, qty 10 — stock is only 5, so this will violate
  -- CHECK (stock_qty >= 0) and abort the whole transaction automatically.
  \echo '--- Attempting to reduce variant 6 stock by 10 (stock is 5) ---'
  UPDATE product_variant SET stock_qty = stock_qty - 10 WHERE variant_id = 6;

  -- This INSERT will be rejected because the transaction is already aborted.
  \echo '--- This INSERT should be rejected (transaction is aborted) ---'
  INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
  VALUES (:order_id, 6, 10, 36500.00);

ROLLBACK;

\echo '--- After ROLLBACK: proving nothing was saved ---'
\echo '--- Order count (must equal 3, not 4) ---'
SELECT COUNT(*) AS order_count FROM orders;

\echo '--- Order items for the rolled-back order (must be 0 rows) ---'
SELECT * FROM order_item WHERE order_id = :order_id;

\echo '--- Stock of variant 3 (must still be 30, not 28) ---'
SELECT variant_id, sku, stock_qty FROM product_variant WHERE variant_id = 3;

\echo '--- Stock of variant 6 (must still be 5) ---'
SELECT variant_id, sku, stock_qty FROM product_variant WHERE variant_id = 6;


-- =============================================================================
-- SCENARIO B: Rollback by application choice
-- The order and stock updates succeed, a failed payment is inserted, and the
-- application decides to cancel the whole attempt, so it runs ROLLBACK.
-- Nothing is saved.
-- =============================================================================

\echo ''
\echo '========== SCENARIO B: Rollback by choice (application cancels) =========='
\echo ''

\echo '--- Stock BEFORE scenario B ---'
SELECT variant_id, sku, stock_qty FROM product_variant WHERE variant_id IN (3, 8);

BEGIN;

  INSERT INTO orders (customer_id, address_id, status, total_amount)
  VALUES (4, 5, 'pending', 0.00)
  RETURNING order_id \gset

  \echo '--- Order inserted: order_id :order_id ---'

  INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
  VALUES (:order_id, 3, 1, 6500.00);

  INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
  VALUES (:order_id, 8, 1, 8000.00);

  UPDATE product_variant SET stock_qty = stock_qty - 1 WHERE variant_id = 3;
  UPDATE product_variant SET stock_qty = stock_qty - 1 WHERE variant_id = 8;

  UPDATE orders
  SET total_amount = (
      SELECT SUM(quantity * unit_price) FROM order_item WHERE order_id = :order_id
  )
  WHERE order_id = :order_id;

  -- Payment attempt fails at the gateway; insert a failed payment record
  INSERT INTO payment (order_id, method, amount, status, reference, paid_at)
  VALUES (:order_id, 'card', 14500.00, 'failed', 'PAY-FAIL-B-' || :order_id, now());

  \echo '--- Payment gateway returned failure. Application rolling back. ---'

ROLLBACK;

\echo '--- After ROLLBACK: proving nothing was saved ---'
\echo '--- Order count (must equal 3) ---'
SELECT COUNT(*) AS order_count FROM orders;

\echo '--- Payment for rolled-back order (must be 0 rows) ---'
SELECT * FROM payment WHERE order_id = :order_id;

\echo '--- Stock after rollback (variant 3 must be 30, variant 8 must be 22) ---'
SELECT variant_id, sku, stock_qty FROM product_variant WHERE variant_id IN (3, 8);


-- =============================================================================
-- SCENARIO C: SAVEPOINT — partial rollback
-- The order has two items. Item 1 (variant 3) succeeds. A SAVEPOINT is set.
-- Item 2 (variant 6, qty 10) fails the stock CHECK, so we ROLLBACK TO SAVEPOINT
-- and continue with item 1 only. The transaction then commits with only item 1.
-- =============================================================================

\echo ''
\echo '========== SCENARIO C: SAVEPOINT — partial rollback, then commit =========='
\echo ''

\echo '--- Stock BEFORE scenario C ---'
SELECT variant_id, sku, stock_qty FROM product_variant WHERE variant_id IN (3, 6);

BEGIN;

  INSERT INTO orders (customer_id, address_id, status, total_amount)
  VALUES (4, 5, 'pending', 0.00)
  RETURNING order_id \gset

  \echo '--- Order inserted: order_id :order_id ---'

  -- Item 1: variant 3, qty 1 — succeeds
  INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
  VALUES (:order_id, 3, 1, 6500.00);

  UPDATE product_variant SET stock_qty = stock_qty - 1 WHERE variant_id = 3;
  \echo '--- Item 1 done (variant 3 stock reduced by 1). Setting SAVEPOINT s1. ---'

  SAVEPOINT s1;

  -- Item 2: variant 6, qty 10 — stock is 5, this will abort to the savepoint
  \echo '--- Attempting item 2 (variant 6, qty 10) which will fail ---'
  UPDATE product_variant SET stock_qty = stock_qty - 10 WHERE variant_id = 6;

  -- The UPDATE failed; roll back to savepoint (undoes item 2 attempt only)
  ROLLBACK TO SAVEPOINT s1;
  \echo '--- Rolled back to savepoint s1. Item 1 is still in the transaction. ---'

  -- Now fix total and commit with item 1 only
  UPDATE orders
  SET total_amount = (
      SELECT SUM(quantity * unit_price) FROM order_item WHERE order_id = :order_id
  )
  WHERE order_id = :order_id;

  UPDATE orders SET status = 'paid' WHERE order_id = :order_id;

  INSERT INTO payment (order_id, method, amount, status, reference, paid_at)
  VALUES (:order_id, 'card', 6500.00, 'successful', 'PAY-SVPT-C-' || :order_id, now());

COMMIT;

\echo '--- After COMMIT: proving only item 1 was saved ---'
\echo '--- The new order ---'
SELECT order_id, status, total_amount FROM orders WHERE order_id = :order_id;

\echo '--- Order items (must be exactly 1 row: variant 3) ---'
SELECT oi.order_item_id, pv.sku, oi.quantity, oi.unit_price
FROM order_item oi
JOIN product_variant pv ON pv.variant_id = oi.variant_id
WHERE oi.order_id = :order_id;

\echo '--- Stock after commit (variant 3 reduced by 1; variant 6 unchanged) ---'
SELECT variant_id, sku, stock_qty FROM product_variant WHERE variant_id IN (3, 6);

\echo '--- Payment ---'
SELECT method, amount, status, reference FROM payment WHERE order_id = :order_id;
