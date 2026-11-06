-- 01-order-commit.sql
-- ThreadHaus Portfolio 3: Transactions and Concurrency
-- Scenario: a successful order placement that commits.
--
-- Customer: Seun Ogundimu (customer_id = 4, address_id = 5)
-- Item 1: variant 3 (Slim Joggers M Black, price 9000.00 9000 6500.00, qty 2)
-- Item 2: variant 8 (Ankara Blouse M Yellow, price 8000.00, qty 1)
-- Expected total: 2 * 6500 + 1 * 8000 = 21000.00
--
-- The transaction:
--   1. Check stock before
--   2. Insert the order
--   3. Insert order_items
--   4. Reduce stock
--   5. Fix total_amount
--   6. Insert a successful payment
--   7. Set order status to 'paid'
--   8. Commit
--   9. Verify after commit

\echo '=== STOCK BEFORE ==='
SELECT variant_id, sku, stock_qty
FROM product_variant
WHERE variant_id IN (3, 8);

BEGIN;

  -- Insert the order with a placeholder total (0.00); we fix it after the items.
  INSERT INTO orders (customer_id, address_id, status, total_amount)
  VALUES (4, 5, 'pending', 0.00)
  RETURNING order_id \gset

  \echo '--- Order inserted with order_id :order_id ---'

  -- Insert item 1: variant 3 (Slim Joggers M Black), qty 2 @ 6500
  INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
  VALUES (:order_id, 3, 2, 6500.00);

  -- Insert item 2: variant 8 (Ankara Blouse M Yellow), qty 1 @ 8000
  INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
  VALUES (:order_id, 8, 1, 8000.00);

  -- Reduce stock for variant 3 (subtract 2)
  UPDATE product_variant SET stock_qty = stock_qty - 2 WHERE variant_id = 3;

  -- Reduce stock for variant 8 (subtract 1)
  UPDATE product_variant SET stock_qty = stock_qty - 1 WHERE variant_id = 8;

  -- Set total_amount to the sum of quantity * unit_price for this order
  UPDATE orders
  SET total_amount = (
      SELECT SUM(quantity * unit_price)
      FROM order_item
      WHERE order_id = :order_id
  )
  WHERE order_id = :order_id;

  -- Insert a successful payment
  INSERT INTO payment (order_id, method, amount, status, reference, paid_at)
  VALUES (
      :order_id,
      'card',
      21000.00,
      'successful',
      'PAY-COMMIT-' || :order_id,
      now()
  );

  -- Mark the order as paid
  UPDATE orders SET status = 'paid' WHERE order_id = :order_id;

COMMIT;

\echo '=== ORDER AFTER COMMIT ==='
SELECT o.order_id, o.status, o.total_amount, c.full_name AS customer
FROM orders o
JOIN customer c ON c.customer_id = o.customer_id
WHERE o.order_id = :order_id;

\echo '=== ORDER ITEMS ==='
SELECT oi.order_item_id, pv.sku, oi.quantity, oi.unit_price,
       oi.quantity * oi.unit_price AS line_total
FROM order_item oi
JOIN product_variant pv ON pv.variant_id = oi.variant_id
WHERE oi.order_id = :order_id;

\echo '=== PAYMENT ==='
SELECT payment_id, method, amount, status, reference
FROM payment
WHERE order_id = :order_id;

\echo '=== STOCK AFTER ==='
SELECT variant_id, sku, stock_qty
FROM product_variant
WHERE variant_id IN (3, 8);

\echo '=== TOTAL CHECK: stored total vs item sum (difference must be 0) ==='
SELECT o.total_amount AS stored_total,
       SUM(oi.quantity * oi.unit_price) AS item_sum,
       o.total_amount - SUM(oi.quantity * oi.unit_price) AS difference
FROM orders o
JOIN order_item oi ON oi.order_id = o.order_id
WHERE o.order_id = :order_id
GROUP BY o.total_amount;
