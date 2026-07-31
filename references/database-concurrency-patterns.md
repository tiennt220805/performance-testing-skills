# Database Concurrency Patterns, Locking, and Bottlenecks

**Note:** Database schemas, connection pool sizes, and query examples in this file illustrate the EShop reference scenario only — substitute the actual database stack and metrics from the target project's `PERF_SPEC.md` and `PERF_PLAN.md`'s Architecture Limits; the concurrency principles, lock diagnostics, and pool sizing formulas are mandatory to preserve.

## 1. SQLite Concurrency & Architecture Limits

**Single-Writer model.** SQLite guarantees ACID isolation via file-level locking rather than a separate DB server process: at most one write transaction may be in progress at any time. When a second transaction attempts to begin a write while another is active, it either waits (if `busy_timeout` is configured) or fails immediately with `SQLITE_BUSY` (the lock is held elsewhere and may clear shortly) or `SQLITE_LOCKED` (a conflict within the same connection/transaction graph). This is not a defect — it is the mechanism that makes SQLite's locking model work without a broker process.

**WAL mode: benefit and limitation.** Write-Ahead Logging changes writes from an in-place rollback journal to an append-only log, which lets readers see a consistent pre-write snapshot without blocking on an in-progress writer — this is WAL's core benefit: **readers no longer block on a writer**. Its limitation is just as important: **WAL does not enable multiple concurrent writers** — writers still fully serialize against each other exactly as in non-WAL mode. This is precisely the field `PERF_PLAN.md`'s Environment Parity Summary Architecture Limits already records an example for (`SQLite single-writer (WAL mode: no)`) — this file does not introduce a parallel concept, it explains why that field's WAL value changes the expected error signature: without WAL, even read-path requests can be blocked during a writer's exclusive lock phase; with WAL, a clean read-path under concurrent writes should show zero `SQLITE_BUSY`, and any occurrence there is a stronger signal of a genuine driver/config issue.

## 2. Client-Server DB Connection Pooling

A widely cited starting-point sizing formula (HikariCP):

$$\text{Pool Size} = (\text{CPU Cores} \times 2) + \text{Effective Spindle Count}$$

This is a starting-point formula published by HikariCP's own authors as a rule of thumb, not a validated answer — "Effective Spindle Count" is close to meaningless on modern SSD/cloud storage with no physical spindles. The number it produces seeds an initial pool size to configure before testing; the actual correct size must be confirmed against real connection-pool wait-time telemetry observed during AUDIT (Layer 3, `rca-layer3-data.md`) — never presented in `PERF_PLAN.md` as if it were a measured fact (Non-Negotiable 1).

`CPU Cores` here refers to the database host's own hardware — not the `Host Machine Specification` `hooks/session-start.sh` captures (which describes the machine running the agent/k6, typically the load generator). These may be entirely different machines; never substitute one for the other.

**Connection Pool Starvation.** When every pool connection is checked out and a new request needs one, that request queues waiting for a slot to free up. This manifests as elevated **TTFB** (`http_req_waiting`, as defined in `slo-cheatsheet.md` §1) even when the database itself is not under heavy per-query execution load — the bottleneck is contention for a pool slot, not necessarily query cost. Confirming this distinction requires checking the pool's own active/idle/waiting metrics (`rca-layer3-data.md` §2), not just the elevated TTFB in isolation.

## 3. Lock Contention & Isolation Levels

- **Table-level lock** — the entire table is locked for the statement/transaction's duration. Coarsest granularity, highest contention risk; common as a fallback in simpler engines or via an explicit `LOCK TABLE`.
- **Row-level lock** — only the rows actually touched by the transaction are locked. The default in most production RDBMSs (Postgres, MySQL/InnoDB), enabling far higher concurrency than table-level locking.
- **Page-level lock** — a middle-ground granularity some engines use, locking a fixed-size storage block containing multiple rows. Can create contention between logically unrelated rows that happen to share a page.
- **Deadlocks** — two or more transactions each hold a lock the other needs, blocking each other indefinitely. The engine detects the cycle and aborts one transaction (the "deadlock victim") to break it. Consistent lock-acquisition ordering across transactions is the standard mitigation, since most deadlocks stem from transactions acquiring the same set of locks in different orders.
- **Long-running transactions** — a transaction holding locks for an extended time (a large batch update, or a transaction left open by an unrelated slow operation) blocks every other transaction needing those same locks for its entire duration. This is the mechanism behind Layer 3 findings that only surface over long elapsed time — see `rca-soak.md` for how this accumulates and is measured across a Soak run's early/late windows; this file does not re-explain that Soak-specific measurement.
- **Isolation levels** (Read Uncommitted → Read Committed → Repeatable Read → Serializable) trade consistency guarantees for lock scope and duration: stricter isolation locks more broadly and holds locks longer, directly increasing contention risk under concurrency.
- **Read-path vs. write-path** — see `rca-layer3-data.md` §3 for the required distinction between these two failure modes; it is not re-explained here.
- **Impact of unindexed queries on lock duration.** Without a usable index, a query may require a full table scan — or a range/gap lock spanning far more rows than it actually matches — while holding its lock. This extends the lock's held duration well beyond what the matched rows alone would require, multiplying contention risk under concurrent load. An unindexed query is frequently the *actual* root cause behind an observed lock-wait spike, with the lock contention itself being only the visible symptom — this is exactly why `rca-layer3-data.md` §2's `EXPLAIN ANALYZE` check is required before concluding "lock contention" as a standalone root cause.

## 4. Diagnostic Signatures for Layer 3 RCA

Signature names below match `SKILL.md`'s Error Signature Distribution table exactly — no new signature names are introduced here.

| Telemetry Signature | DB Bottleneck Type | Notes |
|---|---|---|
| `SQLITE_BUSY` / `SQLITE_LOCKED` in the raw log | SQLite single-writer contention (§1) | Confined to the write-path per `rca-layer3-data.md` §3's read/write distinction |
| Elevated TTFB (`http_req_waiting`) with pool telemetry showing all connections busy, none idle | Connection pool exhaustion/starvation (§2) | Not necessarily slow queries — the wait is for a free pool slot, not query execution |
| `HTTP 5xx` correlated with a deadlock/lock-timeout entry in the DB driver/ORM's own error message | Deadlock or lock-wait-timeout abort (§3) | Distinguish from an application-level 5xx (Layer 2) by checking whether the error message itself names a lock/deadlock condition |
| Write-path `http_req_waiting` degrading disproportionately vs. read-path at the same VU count, worsening specifically in a Soak run's late window | Long-running transaction / accumulating fragmentation (§3) | Feeds `rca-soak.md`'s early/late-window comparison — see that file for the measurement itself |
| High `http_req_waiting` on an otherwise-unlocked route, confirmed via `EXPLAIN ANALYZE` as a full scan | Unindexed query extending effective lock duration (§3) | Root cause is the missing index, not contention per se — see `rca-layer3-data.md` §2's `EXPLAIN ANALYZE` step |
