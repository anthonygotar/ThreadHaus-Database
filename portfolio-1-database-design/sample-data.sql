-- ThreadHaus sample data
-- Course: MIT 8103 Advanced Database Systems, MIVA Open University
--
-- Assumes a fresh database with all identity columns starting at 1.
-- Run schema.sql first, then this file.
-- Names, cities and prices are Nigerian and naira-based.
-- Password hashes and emails are obviously fake.

-- -----------------------------------------------------------------------------
-- staff (3 rows)
-- -----------------------------------------------------------------------------
INSERT INTO staff (full_name, email, password_hash, role) VALUES
    ('Amaka Okafor',   'amaka@threadhaus.example.com',  'hash_amaka_001',  'admin'),
    ('Emeka Nwosu',    'emeka@threadhaus.example.com',  'hash_emeka_002',  'manager'),
    ('Bisi Adeyemi',   'bisi@threadhaus.example.com',   'hash_bisi_003',   'support');

-- -----------------------------------------------------------------------------
-- rider (3 rows)
-- -----------------------------------------------------------------------------
INSERT INTO rider (full_name, phone, is_available) VALUES
    ('Chukwudi Eze',   '08031234567', true),
    ('Tunde Bakare',   '08059876543', false),   -- assigned to active delivery
    ('Ngozi Obi',      '08077654321', true);

-- -----------------------------------------------------------------------------
-- customer (4 rows)
-- -----------------------------------------------------------------------------
INSERT INTO customer (full_name, email, phone, password_hash) VALUES
    ('Funmi Adebayo',  'funmi@example.com',   '07011111111', 'hash_funmi_001'),
    ('Kelechi Ibe',    'kelechi@example.com', '07022222222', 'hash_kelechi_002'),
    ('Hadiza Musa',    'hadiza@example.com',  '07033333333', 'hash_hadiza_003'),
    ('Seun Ogundimu',  'seun@example.com',    '07044444444', 'hash_seun_004');

-- -----------------------------------------------------------------------------
-- address (5 rows)
-- customer_id: Funmi=1, Kelechi=2, Hadiza=3, Seun=4
-- -----------------------------------------------------------------------------
INSERT INTO address (customer_id, street, city, state, is_default) VALUES
    (1, '12 Allen Avenue',         'Lagos',   'Lagos',  true),
    (2, '5 Adeola Odeku Street',   'Lagos',   'Lagos',  true),
    (2, '22 Wuse Zone 5',          'Abuja',   'FCT',    false),
    (3, '8 Kano Road',             'Kano',    'Kano',   true),
    (4, '3 Awolowo Road',          'Ibadan',  'Oyo',    true);

-- -----------------------------------------------------------------------------
-- category (4 rows — top-level then sub)
-- category_id: Clothing=1, Footwear=2, Men=3, Women=4
-- -----------------------------------------------------------------------------
INSERT INTO category (parent_category_id, name) VALUES
    (NULL, 'Clothing'),
    (NULL, 'Footwear'),
    (1,    'Men'),
    (1,    'Women');

-- -----------------------------------------------------------------------------
-- product (4 rows)
-- product_id: 1=Ankara Shirt, 2=Joggers, 3=Agbada Set, 4=Ankara Blouse
-- -----------------------------------------------------------------------------
INSERT INTO product (category_id, name, description, brand, base_price) VALUES
    (3, 'Ankara Print Shirt',  'Short-sleeve ankara cotton shirt',          'ThreadHaus',  8500.00),
    (3, 'Slim Joggers',        'Slim-fit joggers with elastic waistband',    'ThreadHaus',  6000.00),
    (3, 'Agbada Set',          'Three-piece native agbada with embroidery',  'ThreadHaus', 35000.00),
    (4, 'Ankara Blouse',       'Ankara peplum blouse, flared hem',           'ThreadHaus',  7500.00);

-- -----------------------------------------------------------------------------
-- product_variant (9 rows)
-- variant_id assignment (fresh DB):
--   1: Ankara Shirt  M  Blue
--   2: Ankara Shirt  L  Blue
--   3: Slim Joggers  M  Black
--   4: Slim Joggers  L  Black
--   5: Agbada Set    XL Navy
--   6: Agbada Set    XXL Navy
--   7: Ankara Blouse S  Yellow
--   8: Ankara Blouse M  Yellow
--   9: Ankara Blouse M  Red
-- -----------------------------------------------------------------------------
INSERT INTO product_variant (product_id, sku, size, colour, price, stock_qty) VALUES
    (1, 'TH-ANK-M-BLU',   'M',   'Blue',    9000.00,  20),
    (1, 'TH-ANK-L-BLU',   'L',   'Blue',    9000.00,  15),
    (2, 'TH-JOG-M-BLK',   'M',   'Black',   6500.00,  30),
    (2, 'TH-JOG-L-BLK',   'L',   'Black',   6500.00,  25),
    (3, 'TH-AGS-XL-NVY',  'XL',  'Navy',   36000.00,   8),
    (3, 'TH-AGS-XXL-NVY', 'XXL', 'Navy',   36500.00,   5),
    (4, 'TH-ANB-S-YEL',   'S',   'Yellow',  8000.00,  18),
    (4, 'TH-ANB-M-YEL',   'M',   'Yellow',  8000.00,  22),
    (4, 'TH-ANB-M-RED',   'M',   'Red',     8200.00,  12);

-- -----------------------------------------------------------------------------
-- orders (3 rows)
-- Order 1: Funmi, delivered.        total = 1*9000 + 2*6500 = 22000
-- Order 2: Kelechi, in transit.     total = 1*36000 + 1*8000 = 44000
-- Order 3: Hadiza, not yet paid.    total = 2*8200 = 16400
-- -----------------------------------------------------------------------------
INSERT INTO orders (customer_id, address_id, order_date, status, total_amount) VALUES
    (1, 1, '2026-10-01 09:15:00+01', 'delivered', 22000.00),
    (2, 2, '2026-10-10 14:30:00+01', 'shipped',   44000.00),
    (3, 4, '2026-10-20 11:00:00+01', 'pending',   16400.00);

-- -----------------------------------------------------------------------------
-- order_item
-- Order 1 items: variant 1 (Ankara Shirt M Blue x1 @9000), variant 3 (Joggers M Black x2 @6500)
-- Order 2 items: variant 5 (Agbada XL Navy x1 @36000), variant 7 (Ankara Blouse S Yellow x1 @8000)
-- Order 3 items: variant 9 (Ankara Blouse M Red x2 @8200)
-- -----------------------------------------------------------------------------
INSERT INTO order_item (order_id, variant_id, quantity, unit_price) VALUES
    (1, 1, 1,  9000.00),
    (1, 3, 2,  6500.00),
    (2, 5, 1, 36000.00),
    (2, 7, 1,  8000.00),
    (3, 9, 2,  8200.00);

-- -----------------------------------------------------------------------------
-- payment
-- Order 1: one successful card payment
-- Order 2: failed card attempt THEN successful bank_transfer (two payment rows)
-- Order 3: no payment yet (none inserted)
-- -----------------------------------------------------------------------------
INSERT INTO payment (order_id, method, amount, status, reference, paid_at) VALUES
    (1, 'card',          22000.00, 'successful', 'PAY-REF-001', '2026-10-01 09:20:00+01'),
    (2, 'card',          44000.00, 'failed',     'PAY-REF-002', '2026-10-10 14:35:00+01'),
    (2, 'bank_transfer', 44000.00, 'successful', 'PAY-REF-003', '2026-10-10 15:00:00+01');

-- -----------------------------------------------------------------------------
-- delivery
-- Order 1: delivered by rider 1 (Chukwudi)
-- Order 2: in transit, rider 2 (Tunde — hence is_available=false above)
-- Order 3: pending, no rider yet
-- -----------------------------------------------------------------------------
INSERT INTO delivery (order_id, rider_id, status, assigned_at, delivered_at, current_location) VALUES
    (1, 1, 'delivered',  '2026-10-01 10:00:00+01', '2026-10-02 13:45:00+01', NULL),
    (2, 2, 'in_transit', '2026-10-11 08:00:00+01', NULL,                     'Ojodu Bridge, Lagos'),
    (3, NULL, 'pending', NULL,                      NULL,                     NULL);

-- -----------------------------------------------------------------------------
-- return_request (1 row)
-- Funmi returns one Ankara Shirt from order 1 (order_item_id = 1)
-- Assigned to Bisi (staff_id = 3, support)
-- -----------------------------------------------------------------------------
INSERT INTO return_request (order_item_id, staff_id, reason, status, refund_amount) VALUES
    (1, 3, 'Wrong size delivered, requested M but received L', 'approved', 9000.00);

-- -----------------------------------------------------------------------------
-- complaint (2 rows)
-- -----------------------------------------------------------------------------
INSERT INTO complaint (customer_id, staff_id, subject, description, status) VALUES
    (2, 3, 'Delivery delay',
     'My order has been in transit for 3 days with no update.',
     'in_progress'),
    (4, NULL, 'Wrong item colour',
     'I ordered the red blouse but received yellow.',
     'open');

-- -----------------------------------------------------------------------------
-- review (3 rows)
-- UNIQUE (customer_id, product_id) — one review per customer per product
-- -----------------------------------------------------------------------------
INSERT INTO review (customer_id, product_id, rating, comment) VALUES
    (1, 1, 5, 'Beautiful ankara shirt. Fabric quality is excellent.'),
    (1, 2, 4, 'Joggers fit well but the waistband is a bit loose.'),
    (2, 3, 3, 'Agbada is nice but delivery packaging was poor.');
