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


---

## d. Concurrency Problem and Fixes

**The unsafe oversell (`evidence/oversell-unsafe-run.txt`)**

I set variant 3 stock to 1, then started two buyer sessions in parallel. Both sessions ran `SELECT stock_qty` before either committed and both read **1**. Both then wrote `SET stock_qty = 0` and inserted their own order and `order_item`. Both committed. Final state: stock = 0 but two `order_item` rows sold for one unit. This is a lost update: Session 2 overwrote Session 1's stock write because it based its update on a value it had read before Session 1 committed.

**Fix A — SELECT ... FOR UPDATE (`evidence/oversell-for-update-run.txt`)**

Session 1 added `FOR UPDATE` to its `SELECT stock_qty`. This acquired a row lock on variant 3. Session 2 started its `SELECT FOR UPDATE` 1 second later and blocked immediately. From the timestamps: S1 committed at `07:34:41.427` and S2 got its lock at `07:34:41.430` — S2 waited about 1 second for S1 to release. After acquiring the lock S2 re-read stock = 0 and rolled back. Final state: one order placed, stock = 0.

**Fix B — conditional UPDATE (`evidence/oversell-conditional-run.txt`)**

No explicit lock. Instead, both sessions ran:
```sql
UPDATE product_variant SET stock_qty = stock_qty - 1
WHERE variant_id = 3 AND stock_qty >= 1;
```
This UPDATE is atomic. Session 1 matched 1 row and committed. Session 2 ran next and matched 0 rows (stock was already 0). The application treats 0 rows affected as out-of-stock and rolls back. Final state: one order, stock = 0.

Fix A is simpler to read and guarantees the latest stock value is visible after the lock is acquired. It causes more lock contention because the row is held for the duration of the transaction. Fix B avoids explicit locks and scales better under high concurrency, but requires the application to check the UPDATE row count to decide whether to proceed or roll back.


---

## e. Deadlock

**The deadlock (`evidence/deadlock-run.txt`)**

Two sessions each needed to lock variants 3 and 6 but locked them in opposite order:
- Session 1: locked variant 3, slept 1s, then tried to lock variant 6
- Session 2: locked variant 6, slept 1s, then tried to lock variant 3

Each session was waiting for the other to release a lock. This is a circular wait — a deadlock. PostgreSQL detected it and aborted Session 1 with:

```
ERROR: deadlock detected
```

Session 2 then acquired variant 3, committed, and its order was saved. Final state: one order placed.

**How PostgreSQL picks the victim**

PostgreSQL does not pick the cheapest transaction to abort. Instead, each waiting session starts a timer when it begins to wait. The default `deadlock_timeout` is 1 second. The first session whose timer expires runs the deadlock detection check. If a cycle is found, that session is the one aborted — not because it is cheaper, but simply because its timer fired first. In this scenario Session 1 started waiting for variant 6 before Session 2 started waiting for variant 3, so Session 1's timer expired first and it was aborted. This happened on both runs.

**The fix (`evidence/deadlock-fixed-run.txt`)**

Both sessions locked both variants in ascending `variant_id` order in a single statement:

```sql
SELECT variant_id, stock_qty
FROM product_variant
WHERE variant_id IN (3, 6)
ORDER BY variant_id
FOR UPDATE;
```

With the same lock order there is no cycle. Session 2 simply waited for Session 1 to release variant 3 and then proceeded. Both sessions committed. Two orders placed, each variant's stock reduced by 2.


---

## e. Deadlock

**The deadlock (`evidence/deadlock-run.txt`)**

Two sessions each needed to lock variants 3 and 6 but locked them in opposite order:
- Session 1: locked variant 3, slept 1s, then tried to lock variant 6
- Session 2: locked variant 6, slept 1s, then tried to lock variant 3

Each session was waiting for the other to release a lock — a circular wait. PostgreSQL detected it and aborted Session 1 with:

```
ERROR: deadlock detected
```

Session 2 then acquired variant 3, committed, and its order was saved. Final state: one order placed, stock for each variant reduced by 1.

**How PostgreSQL picks the victim**

PostgreSQL does not pick the cheapest transaction to abort. Instead, each waiting session starts an internal timer when it first blocks. The default `deadlock_timeout` is 1 second. The first session whose timer expires runs the deadlock detection algorithm. If a cycle is confirmed, that session is aborted — not because it costs less to undo, but because its timer fired first. In these scenarios Session 1 started waiting for variant 6 first, so its timer expired first and it was aborted. This happened consistently on both runs.

**The fix (`evidence/deadlock-fixed-run.txt`)**

Both sessions locked both variants together in ascending `variant_id` order:

```sql
SELECT variant_id, stock_qty
FROM product_variant
WHERE variant_id IN (3, 6)
ORDER BY variant_id
FOR UPDATE;
```

With the same lock order there is no cycle. Session 2 simply waited for Session 1 to release variant 3, then proceeded. Both sessions committed. Two orders placed, variant 3 stock reduced from 30 to 28, variant 6 stock reduced from 5 to 3.


---

## f. Isolation Levels

PostgreSQL treats `READ UNCOMMITTED` as `READ COMMITTED`. Dirty reads are not possible at any level.

| Isolation level | Dirty read | Non-repeatable read | Phantom read | Write skew |
|---|---|---|---|---|
| READ UNCOMMITTED | Not possible (treated as READ COMMITTED) | Observed (same as RC) | Observed (same as RC) | not tested |
| READ COMMITTED | Not possible | **Observed** — price changed between two reads in same tx | **Observed** — order count changed between two reads | not tested |
| REPEATABLE READ | Not possible | **Prevented** — second read returned snapshot value | **Prevented** — PostgreSQL snapshot blocks phantoms | **Vulnerable** — both sessions committed, rule broken |
| SERIALIZABLE | Not possible | Prevented | Prevented | **Prevented** — one session aborted |

**07 — Non-repeatable read (`evidence/nonrepeatable-read-committed-run.txt`, `evidence/nonrepeatable-read-repeatable-run.txt`)**

Session 1 read variant 3 price twice with a 2-second sleep. Session 2 raised the price by ₦500 and committed in between.

- READ COMMITTED: first read **₦6,500**, second read **₦7,000** — the new price was visible inside the same transaction.
- REPEATABLE READ: first read **₦6,500**, second read **₦6,500** — snapshot held. When Session 1 then tried to UPDATE the same row, PostgreSQL raised: `ERROR: could not serialize access due to concurrent update`. Session 1 was rolled back.

**08 — Phantom read (`evidence/phantom-read-committed-run.txt`, `evidence/phantom-read-repeatable-run.txt`)**

Session 1 counted orders for customer 1 twice. Session 2 inserted a new order for customer 1 in between.

- READ COMMITTED: first count **1**, second count **2** — new row appeared inside the same transaction (phantom).
- REPEATABLE READ: both counts **1** — the snapshot did not include Session 2's insert. Note: the SQL standard says REPEATABLE READ does not prevent phantoms, but PostgreSQL's snapshot isolation does prevent them here.

**09 — Dirty read (`evidence/dirty-read-run.txt`)**

Session 1 updated variant 3 price to ₦99,999 without committing, then slept 3 seconds and rolled back. Session 2 ran at `READ UNCOMMITTED` and read the price during the sleep. Session 2 read **₦6,500**, not ₦99,999. PostgreSQL does not implement dirty reads at any isolation level — `READ UNCOMMITTED` behaves identically to `READ COMMITTED`.

**10 — Write skew (`evidence/write-skew-repeatable-run.txt`, `evidence/write-skew-serializable-run.txt`)**

Rule: at least one rider must remain available. Setup: riders 1 and 2 available, rider 3 unavailable. Each session read count = 2, decided it was safe to mark its own rider unavailable, and proceeded.

- REPEATABLE READ: both sessions committed. Final count of available riders: **0** — the rule was broken. This is write skew: each session read a consistent snapshot but their combined writes violated the invariant.
- SERIALIZABLE: Session 2 got: `ERROR: could not serialize access due to read/write dependencies among transactions` and was rolled back. Session 1 committed (rider 1 unavailable). Session 2 then retried, read count = 1, and did nothing. Final count: **1** — rule preserved.


---

## g. Analysis

**Stock updates: row lock or conditional UPDATE at READ COMMITTED**

For stock updates ThreadHaus should use either `SELECT ... FOR UPDATE` (Fix A) or the conditional `UPDATE ... WHERE stock_qty >= 1` (Fix B) at the default `READ COMMITTED` level. The unsafe version — read stock, sleep, write back a computed value — produced an oversell in every run: both sessions read stock = 1 and both committed, leaving stock = 0 with two `order_item` rows sold (`evidence/oversell-unsafe-run.txt`). Neither REPEATABLE READ nor SERIALIZABLE would fix this specific bug, because the problem is not a phantom or a serialization anomaly — it is a write based on a stale read.

Fix A (`SELECT FOR UPDATE`) is straightforward: the row lock serialises access so only one session proceeds at a time. The evidence shows Session 2 waited about 1 second for Session 1's lock (`evidence/oversell-for-update-run.txt`, timestamps 07:34:40.419 to 07:34:41.430). The cost is contention: every buyer for the same variant queues behind the current lock holder. Under high traffic this can become a bottleneck, and if two transactions each lock multiple variants in different orders, a deadlock is possible — as shown in `evidence/deadlock-run.txt`.

Fix B (conditional UPDATE) avoids explicit locking. The UPDATE itself is atomic. Session 2's update matched 0 rows and rolled back without ever waiting (`evidence/oversell-conditional-run.txt`). The cost is that the application must inspect the row count after the UPDATE and branch accordingly. It is harder to read but scales better under load because there is no lock to queue behind.

**SERIALIZABLE for invariants like rider availability**

The write skew scenario shows that REPEATABLE READ is not enough when a rule depends on an aggregate across multiple rows. Both sessions read count = 2 and both committed, leaving zero riders available — a violated invariant. SERIALIZABLE caught the anomaly and aborted Session 2 (`evidence/write-skew-serializable-run.txt`). The cost is that the application must be written to retry on serialization failure. The retry in `10b-writeskew-s2-retry.sql` read count = 1, decided it could not proceed, and rolled back cleanly. SERIALIZABLE is worth that complexity for rules that cannot be enforced by a single-row lock, but for simple stock decrement it adds unnecessary overhead.

**Summary of protection costs**

- Row lock (`FOR UPDATE`): waiting, reduced throughput on hot rows, deadlock risk if multiple rows are locked in inconsistent order.
- Conditional UPDATE: no waiting, but requires application-level row-count checking.
- SERIALIZABLE: prevents all anomalies, but aborted transactions must be retried; higher overhead per transaction.

---

## h. Limitations

All concurrency is simulated with fixed `pg_sleep()` delays and exactly two sessions. On a real system with many concurrent buyers the race windows would be smaller or larger depending on load, hardware, and network latency. The timings in the evidence are not benchmarks and vary between runs.

The data is the small sample set from portfolio 1. Tests with larger data volumes or dozens of concurrent sessions might show different planner and lock behaviour. I did not test lock timeout settings, `deadlock_timeout` tuning, or the performance impact of SERIALIZABLE under realistic load. Write performance (insert and update throughput with locks in place) was not measured.

