-- ThreadHaus constraint tests
-- Each statement below should FAIL. The comment above each one says what it tests.
-- No ON_ERROR_STOP, so psql continues after each failure and we see all errors.
-- Run after schema.sql and sample-data.sql on a populated database.

-- -----------------------------------------------------------------------------
-- Test 1: negative stock_qty violates CHECK (stock_qty >= 0)
-- -----------------------------------------------------------------------------
INSERT INTO product_variant (product_id, sku, size, colour, price, stock_qty)
VALUES (1, 'TH-BAD-001', 'M', 'Green', 5000.00, -1);

-- -----------------------------------------------------------------------------
-- Test 2: rating of 6 violates CHECK (rating BETWEEN 1 AND 5)
-- -----------------------------------------------------------------------------
INSERT INTO review (customer_id, product_id, rating, comment)
VALUES (3, 2, 6, 'Too good for a 5-star scale');

-- -----------------------------------------------------------------------------
-- Test 3: duplicate customer email violates UNIQUE (email)
-- funmi@example.com is already in the table from sample-data.sql
-- -----------------------------------------------------------------------------
INSERT INTO customer (full_name, email, phone, password_hash)
VALUES ('Duplicate Funmi', 'funmi@example.com', '07099999999', 'hash_dup_001');

-- -----------------------------------------------------------------------------
-- Test 4: delete a customer who has orders violates FK ON DELETE RESTRICT
-- customer_id 1 (Funmi) has orders, so this must be blocked
-- -----------------------------------------------------------------------------
DELETE FROM customer WHERE customer_id = 1;

-- -----------------------------------------------------------------------------
-- Test 5: second delivery for order 1 violates UNIQUE (order_id) on delivery
-- order 1 already has a delivery row from sample-data.sql
-- -----------------------------------------------------------------------------
INSERT INTO delivery (order_id, rider_id, status)
VALUES (1, 3, 'pending');
