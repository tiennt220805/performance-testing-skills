# Layer 2: Application Runtime & Concurrency

**Note:** Route paths, field names, and figures in this file's examples (`/api/cart`, `productId`, `{{...}}` values, etc.) illustrate the EShop reference scenario only — substitute the actual `In-Scope Routes`/fields from the target project's `PERF_SPEC.md`; only the diagnostic technique (metrics to collect, verification commands, layer-attribution logic) is mandatory to preserve.

Loaded unconditionally, together with the other three layer files, during AUDIT Step 3 — every full-load AUDIT run inspects all 4 layers regardless of where the suspected bottleneck lies (Non-Negotiable 3, `bottleneck-auditor.md`'s 4-layer enforcement). This differs from the Strategy Audit Matrix files (`rca-load-stress.md`/`rca-spike.md`/`rca-soak.md`), which ARE conditionally JIT-selected — exactly one, matching the declared strategy. The 4 layer files are never conditionally selected.

## Scope

Node.js event-loop blocking/lag, JVM GC pause stalls, thread-pool starvation, Python GIL contention, unhandled async rejections/promise leaks, and unbounded in-memory growth (caches, session stores, token maps).

## 1. Symptom Telemetry Signatures

- p99 (and often p95) latency blows up while SUT-side CPU utilization hasn't reached 100% — the classic "something is blocking, not just busy" signature.
- Event-loop delay measurements (where the SUT exposes them) exceeding a sustained danger threshold (commonly cited as >50ms).
- GC pause spikes visible in runtime logs correlating with latency spikes at the same wall-clock timestamp in the k6 raw log.
- Active thread-pool count pinned at its configured maximum with a growing request queue behind it.
- RSS climbing monotonically across the run with no plateau — a leak or unbounded-cache signature (see §3).

## 2. Diagnostic Metrics & Verification Commands

**k6-observable:** correlate `http_req_waiting` (TTFB) spikes against wall-clock timestamps in the raw log — look for spikes with no corresponding Layer 1 (connection) or Layer 3 (DB) signal at the same moment; an unexplained TTFB spike with clean transport and clean DB evidence usually resolves to Layer 2.

**OS/process-level — only when the Master has direct access to the SUT host.** Otherwise write `No direct OS access — inferring from k6-observable signals only` in the report — never fabricate a reading:

- `top -H -p {{PID}}` / `htop` — per-thread CPU; distinguishes a single thread pinned at 100% (GIL/single-threaded event-loop signature) from many threads all busy (real parallel saturation).
- Runtime-specific profiling: Node `--prof`/flame graphs, JVM `jstack`/GC logs (`-Xlog:gc*`), Python `py-spy dump`.
- `ps -o rss= -p {{PID}}` sampled at intervals across the run — the raw RSS trend feeding the Soak degradation check in §3.

## 3. Soak Time-Windowed Linkage — Reusing `earlyWindowLatency`/`lateWindowLatency`

When the strategy under audit is **Soak**, this layer's evidence must be built from the exact `earlyWindowLatency`/`lateWindowLatency` `Trend` metrics defined in `profile-soak-test.md` §4 — do not invent a separate mechanism. Latency that is flat across the entire run but merely high is a *different* defect (a design/config problem, present from minute one) than latency that starts low and only degrades in the late window — the latter is the canonical Layer 2 signature of a leak: an in-memory cache, session store, or event listener growing across the run and only becoming expensive once large enough. Compare `lateWindowLatency`'s p95 against `earlyWindowLatency`'s p95 exactly as `profile-soak-test.md` §5 defines (the >20% degradation heuristic) before attributing a Soak-strategy bottleneck to this layer — a flat-but-high reading across both windows points elsewhere (a Layer 2 design issue present from the start, or Layer 3/4 if RSS/CPU show that same flat-but-high pattern).

## 4. Distinction from Other Layers

- CPU pegged at 100% *with no widening latency gap and no growing queue* is not automatically a Layer 2 bottleneck — confirm the p99/p95 gap actually widened, not just that CPU is busy; a compute-bound workload operating at high utilization exactly as designed is not necessarily "broken."
- A DB-driven latency spike (Layer 3) can masquerade as Layer 2 if the application thread is blocked waiting on a synchronous DB call — check Layer 3's evidence (`http_req_waiting` correlated with DB pool wait time) before concluding the application runtime itself is the bottleneck.

## 5. Worked Example — Soak Early/Late Window Comparison

```text
Trend summary at report time (see profile-soak-test.md §4 for how these are populated):
  latency_early_window (first 15 min)..: avg=118ms  p95=210ms
  latency_late_window (last 15 min)....: avg=340ms  p95=890ms

RSS sampled via `ps -o rss=`:
  t=0min:    142 MB
  t=60min:   410 MB
  t=118min:  1.2 GB   (no plateau reached before test end)
```

p95 degraded 890ms vs. 210ms — a 324% increase, far past the >20% internal heuristic threshold from `profile-soak-test.md` §5 — while RSS climbed monotonically with no plateau across the full run. This is not "the route is slow" (that would show up flat in *both* windows); it is a canonical Layer 2 leak signature. **Verdict: unbounded in-memory growth (Layer 2)** — the specific structure would need code-level identification (e.g. a session map with no eviction) before recommending a fix, per §6 below.

Contrast this with a route whose early-window and late-window p95 are both ~800ms with flat RSS — that pattern indicates a Layer 2 *design* issue present from minute one (e.g. an inherently expensive synchronous computation on every request), not a leak, and does not get attributed to "degradation."

## 6. Remediation Boundaries

- Confirmed event-loop blocking traced to a specific synchronous operation → recommend making that specific operation asynchronous/offloaded, never a generic "optimize the code" statement.
- Confirmed unbounded growth via the Soak early/late comparison → recommend adding eviction/TTL to the specific structure identified, never a blanket "fix the memory leak" without naming what's leaking.
- Never recommend a runtime/framework swap (e.g. "switch off Node.js") — that conclusion is outside what a single load test's evidence can support.

## 7. Feeding the RCA Matrix

Reduce to one `Evidence` / `Verdict` row — e.g. `Evidence: p95 latency degraded {{PERCENT}}% from early-window ({{EARLY_P95}}ms) to late-window ({{LATE_P95}}ms); RSS climbed from {{EARLY_RSS}}MB to {{LATE_RSS}}MB with no plateau` / `Verdict: Root cause — unbounded in-memory growth (Layer 2)`, or `Verdict: No signal at this layer`. Any `5xx` count traced to an application-level exception (not a DB driver error) maps to the Error Signature Distribution table's "HTTP 5xx" row — attribute it to Layer 2 specifically when the stack trace/log line points at application code rather than a persistence-layer error.
