# Strategy Audit Matrix: Soak

**Note:** Metrics and scenario examples in this file illustrate the EShop reference scenario only — substitute the actual metrics/routes from the target project's `PERF_SPEC.md`; only the diagnostic matrix and 4-layer decision logic are mandatory to preserve.

Loaded conditionally by AUDIT's JIT Protocol during Step 3 — exactly ONE of the three Strategy Audit Matrix files (`rca-load-stress.md` / `rca-spike.md` / `rca-soak.md`) is loaded, matching the `Declared Test Strategy` under audit for this run; the other two are left unread, even for a multi-strategy engagement (each strategy's AUDIT pass loads only its own matrix). This is the opposite of the four layer files, which are always loaded together in full regardless of strategy.

## Scope

An **overlay** on `rca-layer1-transport.md` → `rca-layer4-infrastructure.md` — it does not re-explain how to read RSS trends or DB pool metrics. Soak AUDIT diagnoses time-dependent degradation over a sustained, moderate-load, multi-hour run — memory leaks and connection-pool/DB fragmentation accumulating over time, per `profile-soak-test.md` §1.

## Diagnostic Matrix

| Symptom | Primary Layer to Check First | Why |
|---|---|---|
| RSS climbs monotonically across the run with no plateau | Layer 2 — Application | Canonical unbounded in-memory growth signature (cache/session store/token map with no eviction) — see `rca-layer2-application.md` §3 for the full early/late-window mechanism |
| DB connection-pool wait times climb across the run even though VU count is flat | Layer 3 — Data | Connection-pool exhaustion or DB-side fragmentation accumulating over hours, not visible at Load-test durations |
| Latency is high from minute one and stays flat across the whole run | Not Soak's primary finding | A flat-but-high reading is a design/config issue present from the start (see `rca-layer2-application.md` §3) — do not report this as Soak degradation; it would have shown up in a Load test too |
| Disk usage or log file size grows unboundedly across the run | Layer 4 — Infrastructure | A long-running-specific symptom: log/disk fill that a short Load test would never surface |

## Strategy-Specific Threshold Logic

Reuses `profile-soak-test.md` §4–§5's time-windowed mechanism verbatim — never redefine it: the `earlyWindowLatency`/`lateWindowLatency` `Trend` metrics (first 15 min vs. last 15 min), compared with the **>20% degradation heuristic**. `rca-layer2-application.md` §3 already documents this mechanism's full mechanics and its Layer 2 vs. "flat-but-high" distinction in detail — this file does not repeat that explanation, only confirms it is the mandatory basis for any Soak-strategy Layer 2/3 finding.

**The flat-vs-degrading distinction is the single most important filter for Soak AUDIT**: a route with poor performance in *both* windows is not a Soak-specific finding at all (it would show up identically in a 10-minute Load test) — only report it as a Soak finding when the late-window reading is measurably worse than the early-window reading by the >20% threshold.

## Worked Example

```text
latency_early_window: p95=210ms
latency_late_window:  p95=890ms   -> 324% increase, past the >20% threshold

RSS trend: 142MB (t=0) -> 1.2GB (t=118min), no plateau reached

DB pool wait time: 8ms avg (first hour) -> 340ms avg (final hour), pool size unchanged
```

Both Layer 2 (RSS) and Layer 3 (pool wait time) show time-dependent degradation correlated with the same late-window latency blow-up — this is not necessarily "pick one layer"; both may be contributing (e.g. a growing in-memory structure holding DB connections open longer than it should). Report both layers' evidence separately rather than collapsing to a single verdict.

**Flat-but-high — contrast case, not a Soak finding:**

```text
latency_early_window: p95=780ms
latency_late_window:  p95=810ms   -> 3.8% increase, well under the >20% threshold

RSS trend: 210MB (t=0) -> 235MB (t=118min) — stable, no meaningful growth
```

p95 is poor in *both* windows, but the delta between them is nowhere near the >20% degradation threshold, and RSS stays flat. This route is simply slow by design (or misconfiguration) from minute one — it would have shown the exact same 780–810ms reading in a 10-minute Load test. **Do not report this as a Soak-strategy finding**; it belongs in the Load/Stress SLO comparison instead (see `rca-load-stress.md`), not in this file's degradation analysis.

## Feeding the RCA Matrix

Each contributing layer gets its own `Evidence`/`Verdict` row in `SKILL.md`'s 4-Layer RCA Inspection Matrix — Soak is the strategy most likely to legitimately implicate more than one layer at once, so do not force a single root cause when the evidence supports multiple contributing layers. E.g. `Evidence: p95 degraded {{PERCENT}}% early-to-late window; RSS climbed {{EARLY_RSS}}MB -> {{LATE_RSS}}MB with no plateau` / `Verdict: Root cause — unbounded in-memory growth (Layer 2)`, alongside a separate Layer 3 row citing the pool-wait-time trend. No new Error Signature Distribution row is needed beyond what `rca-layer2-application.md`/`rca-layer3-data.md` already define — attribute any `5xx`/`SQLITE_BUSY` counts discovered in the late window to their existing rows, noting the time-dependent onset in this file's own Evidence line.
