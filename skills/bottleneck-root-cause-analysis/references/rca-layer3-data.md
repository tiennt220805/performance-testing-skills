# Layer 3: Persistence, Database & Locking

**Note:** Route paths, field names, and figures in this file's examples (`/api/cart`, `productId`, `{{...}}` values, etc.) illustrate the EShop reference scenario only — substitute the actual `In-Scope Routes`/fields from the target project's `PERF_SPEC.md`; only the diagnostic technique (metrics to collect, verification commands, layer-attribution logic) is mandatory to preserve.

Loaded unconditionally, together with the other three layer files, during AUDIT Step 3 — every full-load AUDIT run inspects all 4 layers regardless of where the suspected bottleneck lies (Non-Negotiable 3, `bottleneck-auditor.md`'s 4-layer enforcement). This differs from the Strategy Audit Matrix files (`rca-load-stress.md`/`rca-spike.md`/`rca-soak.md`), which ARE conditionally JIT-selected — exactly one, matching the declared strategy. The 4 layer files are never conditionally selected.

## Scope

DB connection-pool exhaustion, single-writer lock contention (e.g. SQLite `SQLITE_BUSY`/`SQLITE_LOCKED`), missing indexes producing full scans under concurrency, deadlocks, and slow-query accumulation that wasn't visible at VERIFY's 1 VU scale.

## 1. Symptom Telemetry Signatures

- `http_req_waiting` (TTFB) increases sharply as concurrent VUs rise, while `http_req_connecting`/`http_req_blocked` (Layer 1) stay flat — the delay is happening after the connection succeeded, inside the SUT's processing.
- Raw log entries: `SQLITE_BUSY: database is locked`, `SQLITE_LOCKED`, `deadlock detected`, `timeout acquiring connection from pool`.
- Write-path endpoints (`POST`/`PUT`/`PATCH`) degrading disproportionately versus read-path (`GET`) endpoints at the same VU count — a classic single-writer contention signature.

## 2. Diagnostic Metrics & Verification Commands

**k6-observable:** per-`group()` `http_req_waiting` broken out by HTTP method — compare the write-group's p95 against the read-group's p95 at the same point in the ramp; a write-only degradation is the primary Layer 3 tell.

**DB/host-level — only when the Master has direct access to the DB host or its admin interface.** Otherwise write `No direct OS access — inferring from k6-observable signals only` — never invent a pool-utilization or lock-wait number that wasn't actually queried:

- DB connection-pool metrics (`pg_stat_activity` for Postgres, driver-level pool stats for Node/JVM ORMs) — active vs. idle vs. waiting connections at peak load.
- `EXPLAIN ANALYZE`/slow-query log entries for the routes showing the worst `http_req_waiting` degradation — confirms whether an unindexed scan is the actual cause versus lock contention.
- For SQLite specifically: whether WAL mode is enabled (readers don't block writers under WAL, but writers still serialize against each other) — this changes which failure signature to expect.

## 3. Read-Path vs. Write-Path — Never Conflate

`bottleneck-auditor.md` requires this distinction explicitly: *"Distinguish read-path errors from write-path lock contention — they imply different fixes and must not be conflated in the report."*

- **Write-path lock contention** (`SQLITE_BUSY`, deadlocks, write-queue backlog): the fix is architectural — batching writes, moving to a multi-writer datastore, or shrinking transaction scope/duration. It has nothing to do with query optimization.
- **Read-path errors** (slow unindexed `SELECT`s, read-replica lag, connection-pool exhaustion from too many concurrent reads): the fix is query/index-level or pool-sizing, and requires no change to the write path at all.

A report that says "the database is slow" without stating which of these two it is has not actually completed Layer 3 analysis — always name which path (or both, if both are separately evidenced) is implicated, each with its own evidence line.

## 4. Distinction from Other Layers

- High DB-host CPU with the *application* host's CPU low is a strong Layer 3 (not Layer 2) signal — the bottleneck sits on the persistence tier, not the application runtime.
- A connection-pool-exhaustion error is a Layer 3 symptom even though the pool object lives inside the application process — the root cause is DB-side capacity (too few connections available for the concurrency, or the DB too slow to free connections back fast enough), not application logic.

## 5. Worked Example — Isolating Write-Path Lock Contention

```text
Raw log excerpt (perf-test/logs/baseline-audit.log):
  SQLITE_BUSY: database is locked  (x47 occurrences, all on POST /api/checkout)
  SQLITE_BUSY: database is locked  (x0 occurrences on GET /api/search or GET /api/cart)

Per-group http_req_waiting (k6 summary):
  group:::checkout (POST).......: p95=2.4s   <- write-path
  group:::search (GET)..........: p95=180ms  <- read-path, unaffected
  group:::cart (GET)............: p95=165ms  <- read-path, unaffected
```

All 47 `SQLITE_BUSY` occurrences are confined to the one write-path route; both read-path routes remain within their `PERF_SPEC.md` targets throughout. This asymmetry — write-path degraded, read-path clean — is the signature that rules *in* write-path lock contention and rules *out* a general DB capacity problem (a general capacity issue would degrade reads too). **Verdict: single-writer lock contention (Layer 3, write-path)** — confirmed via `EXPLAIN ANALYZE` that the query itself is well-indexed, so the fix is architectural (reduce transaction scope / batch writes), not query optimization.

## 6. Remediation Boundaries

- Confirmed `SQLITE_BUSY` correlated with concurrent write VUs → recommend batching/serializing writes or evaluating a multi-writer datastore, never "just add retries" as the primary fix (retries mask the symptom without addressing the underlying serialization limit).
- Confirmed unindexed scan via `EXPLAIN ANALYZE` → recommend the specific missing index, never a generic "optimize queries" statement.
- Never recommend a schema migration or datastore replacement without the slow-query/lock evidence directly supporting that specific change.

## 7. Feeding the RCA Matrix

Reduce to one `Evidence` / `Verdict` row — e.g. `Evidence: SQLITE_BUSY x{{COUNT}} correlated with POST /api/checkout at {{VU_COUNT}}+ concurrent VUs; write-group p95 {{WRITE_P95}}ms vs. read-group p95 {{READ_P95}}ms` / `Verdict: Root cause — single-writer lock contention (Layer 3, write-path)`, or `Verdict: No signal at this layer`. Every `SQLITE_BUSY`/`SQLITE_LOCKED` occurrence in the raw log maps directly to the Error Signature Distribution table's "SQLITE_BUSY / SQLITE_LOCKED" row, attributed to Layer 3 — Data.
