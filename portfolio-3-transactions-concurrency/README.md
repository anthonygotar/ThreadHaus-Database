# Portfolio 3: Transactions and Concurrency

**MIT 8103 Advanced Database Systems**
Anthony Gotar

---

## a. Setup

I used the `threadhaus` database from portfolio 1 for all scenarios. The database was loaded from `portfolio-1-database-design/schema.sql` and `portfolio-1-database-design/sample-data.sql`, giving 4 customers, 3 orders, 9 product variants and known stock values.

`reset-db.sh` drops and recreates the database before every scenario. This keeps the starting state identical across runs so results are comparable. The script also calls `pg_terminate_backend` first to close any lingering idle connections, which would otherwise block the `DROP DATABASE`.

PostgreSQL version installed: **18.6** (Ubuntu 18.6-0ubuntu0.26.04.1).

Two sessions are simulated by starting two `psql` processes as bash background jobs and waiting for both to finish. Each SQL file uses `pg_sleep()` to pause at key points and force the sessions to overlap in a controlled way. Every important step prints `clock_timestamp()` so the output shows the exact interleaving. Each scenario was run twice with the same result.

---

## b. Commit

`01-order-commit.sql` places a full order for Seun Ogundimu (customer 4, address 5) inside a single transaction. The steps are:

1. Record stock before (variant 3: 30, variant 8: 22)
2. `BEGIN`
3. Insert the order with `total_amount = 0.00` and capture the new `order_id` with `RETURNING ... \gset`
4. Insert two `order_item` rows (variant 3 × 2 at ₦6,500; variant 8 × 1 at ₦8,000)
5. Reduce `stock_qty` on both variants
6. `UPDATE orders SET total_amount = (SELECT SUM(...))` to fix the total
7. Insert a successful `card` payment with reference `PAY-COMMIT-4`
8. Set `orders.status = 'paid'`
9. `COMMIT`

After commit (from `evidence/commit-run.txt`):

- Order id: **4**, status: **paid**, total: **₦21,000.00**, customer: Seun Ogundimu
- Variant 3 stock: 30 → **28** (2 sold)
- Variant 8 stock: 22 → **21** (1 sold)
- Total check: stored 21,000.00 − item sum 21,000.00 = **0.00**

---

## c. Rollback

`02-order-rollback.sql` runs three scenarios on a fresh database. The order IDs in the output show gaps caused by rolled-back transactions: identity sequences advance even when a transaction rolls back, so aborted orders leave holes in the ID sequence.

**Scenario A — automatic abort (CHECK constraint)**

Session tries to reduce variant 6 stock by 10, but stock is only 5. The `UPDATE` violates `CHECK (stock_qty >= 0)`. PostgreSQL aborts the transaction automatically. The next command in the same session gets: `ERROR: current transaction is aborted, commands ignored until end of transaction block`. After `ROLLBACK`:
- Order count: still **3** (no new row committed)
- Variant 3 stock: still **30** (the first item's stock reduction was rolled back too)
- Variant 6 stock: still **5**

**Scenario B — rollback by choice**

The order and stock updates succeed, a `failed` payment is inserted, then the application decides to cancel with `ROLLBACK`. After rollback:
- Order count: still **3**
- No payment row for the rolled-back order
- Variant 3 and 8 stock: unchanged (30 and 22)

**Scenario C — SAVEPOINT**

An order with two items. Item 1 (variant 3 × 1) works. `SAVEPOINT s1` is set. Item 2 (variant 6 × 10) fails the stock CHECK. `ROLLBACK TO SAVEPOINT s1` undoes the item 2 attempt only. The transaction continues with item 1 and commits. From `evidence/rollback-run.txt`:
- Order id **6**, status: **paid**, total: **₦6,500.00**
- Only one `order_item` row: variant 3
- Variant 3 stock: 30 → **29** (1 sold)
- Variant 6 stock: still **5** (item 2 attempt rolled back)

The gaps in order IDs confirm the identity counter advanced during scenarios A and B even though those transactions were rolled back.

