# Layer 4: Infrastructure & OS Resources

**Note:** Route paths, field names, and figures in this file's examples (`/api/cart`, `productId`, `{{...}}` values, etc.) illustrate the EShop reference scenario only — substitute the actual `In-Scope Routes`/fields from the target project's `PERF_SPEC.md`; only the diagnostic technique (metrics to collect, verification commands, layer-attribution logic) is mandatory to preserve.

Loaded unconditionally, together with the other three layer files, during AUDIT Step 3 — every full-load AUDIT run inspects all 4 layers regardless of where the suspected bottleneck lies (Non-Negotiable 3, `bottleneck-auditor.md`'s 4-layer enforcement). This differs from the Strategy Audit Matrix files (`rca-load-stress.md`/`rca-spike.md`/`rca-soak.md`), which ARE conditionally JIT-selected — exactly one, matching the declared strategy. The 4 layer files are never conditionally selected.

## Scope

Host CPU saturation, RAM exhaustion leading to paging/swapping, disk I/O saturation (`iowait`), and container-level CPU throttling (cgroups CFS quota) — the hardware/OS floor beneath everything the other three layers run on top of.

## 1. Symptom Telemetry Signatures

- CPU `iowait` % elevated — the CPU is idle-but-blocked waiting on disk, not actually compute-bound.
- Non-zero swap usage appearing partway through the run — RAM pressure forcing the OS to page, degrading every layer above it simultaneously.
- cgroups `nr_throttled` (CFS quota throttling counter) incrementing — the container is CPU-capped below what the process is actually trying to use, producing latency that looks like an application slowdown but is actually an infrastructure ceiling.
- Disk read/write queue depth climbing alongside `http_req_waiting` — a genuine storage bottleneck underneath a DB- or file-write-heavy route.

## 2. Diagnostic Metrics & Verification Commands

**k6-observable:** none directly — Layer 4 signals are almost entirely OS-side. The only k6-observable proxy is a latency-degradation pattern that doesn't resolve cleanly to Layers 1–3, ruled in by elimination as well as by direct OS evidence when available.

**OS/host-level — only when the Master has direct access to the SUT host.** Otherwise write `No direct OS access — inferring from k6-observable signals only` — never fabricate an `iowait`/swap/throttling figure that wasn't actually sampled:

- `vmstat 1` — the `wa` column for iowait %, `si`/`so` columns for swap-in/swap-out activity.
- `iostat -xz 1` — per-device `%util` and queue depth (`avgqu-sz`), confirms whether disk is actually saturated versus merely busy.
- `cat /sys/fs/cgroup/cpu.stat` (cgroups v2) or `cat /sys/fs/cgroup/cpu/cpu.stat` (v1) — `nr_throttled`/`throttled_time` for container CPU-quota throttling.
- `free -m` sampled across the run — RAM headroom trend, feeding the same kind of early/late comparison Layer 2 uses for leak detection.

## 3. Cold-Cache Penalty vs. Genuine Disk-Bound Bottleneck

`bottleneck-auditor.md` requires this distinction explicitly: *"a cold-cache penalty on the first run is not the same defect as a genuine disk-bound bottleneck on repeated runs."*

- **Cold-cache penalty**: elevated I/O/`iowait` concentrated on the *first* request(s) to a given route or data page after a clean restart (PLAN's mandatory restart-before-comparative-run rule guarantees a cold cache at run start) — the OS page cache hasn't warmed yet. This is expected, transient, and resolves within the first handful of requests to that route.
- **Genuine disk-bound bottleneck**: elevated I/O/`iowait` that persists or recurs steadily across the *entire* run, not just the opening requests — the working set genuinely exceeds what the page cache can hold, or the storage backend itself is the ceiling.

The test: bucket I/O evidence by elapsed time (or request ordinal), the same way Layer 2's Soak analysis buckets latency — if the I/O spike is confined to the first `{{N}}` requests of a route and flattens out afterward, label it a cold-cache artifact, not a bottleneck; if it recurs at a steady rate throughout the run, it's real.

## 4. Distinction from Other Layers

- Swap activity degrades *every* layer simultaneously (application, DB, transport all slow down together) — if Layer 2 and Layer 3 both show unexplained, correlated degradation at the same timestamp with no distinct root cause of their own, check Layer 4 for swap/memory pressure before attributing the degradation separately to each.
- CFS throttling can produce a Layer-2-looking symptom (CPU-bound-looking latency, event-loop-lag-looking stalls) purely from the container's quota, with the application code itself doing nothing wrong — always check `nr_throttled` before concluding an application-level CPU bottleneck when running in a container/cgroup-limited environment.

## 5. Worked Example — Cold-Cache vs. Genuine Disk-Bound

**Case A — cold-cache artifact:**

```text
iostat -xz 1 samples, bucketed by request ordinal for GET /api/reports/export:
  Requests 1-5:    %util=94%  avgqu-sz=6.2   <- first hits after clean restart
  Requests 6-50:   %util=8%   avgqu-sz=0.3   <- flattens immediately after
```

The I/O spike is confined to the first 5 requests immediately following PLAN's mandatory restart, then flattens for the remaining 45 — this is the OS page cache warming up, not a bottleneck. **Verdict: No signal at this layer** (cold-cache artifact, expected and transient).

**Case B — genuine disk-bound bottleneck:**

```text
iostat -xz 1 samples, bucketed by request ordinal for the same route on a larger dataset:
  Requests 1-5:     %util=96%  avgqu-sz=7.1
  Requests 6-50:    %util=89%  avgqu-sz=6.4   <- does not flatten
  Requests 51-200:  %util=91%  avgqu-sz=6.8   <- persists for the rest of the run
```

`%util` and queue depth stay elevated for the entire run, not just the opening requests — the working set genuinely exceeds what the page cache can hold. **Verdict: genuine disk-bound bottleneck (Layer 4)** — recommend faster storage or a smaller working set, not "wait for cache warm-up" (it already has, and the I/O pressure hasn't relented).

## 6. Remediation Boundaries

- Confirmed swap activity → recommend increasing host/container RAM allocation or reducing the SUT's memory footprint (in coordination with any Layer 2 leak finding), never a code-level fix framed as if it were the OS-level problem.
- Confirmed CFS throttling → recommend raising the container's CPU quota/limit, not "optimize the application" — the application may be performing exactly as expected for the CPU it's actually been allocated.
- Confirmed genuine disk-bound I/O (ruled out as cold-cache) → recommend faster storage or reducing the working-set size, never "add more caching" without confirming the existing cache isn't already the working-set-exceeding culprit.

## 7. Feeding the RCA Matrix

Reduce to one `Evidence` / `Verdict` row — e.g. `Evidence: iowait sustained at {{IOWAIT_PERCENT}}% from request {{N}} onward (not just the opening requests); cgroups nr_throttled incremented by {{COUNT}} during the hold phase` / `Verdict: Root cause — container CPU throttling (Layer 4)`, or `Verdict: No signal at this layer`. Layer 4 findings don't map to a dedicated Error Signature Distribution row by default (that table tracks request-level error signatures) — if a `5xx`/timeout was ultimately traced back to a Layer 4 cause (e.g. a swap-induced timeout), still log it under the appropriate request-level row in Error Signature Distribution, but note the Layer 4 attribution in this file's own Evidence line and cross-reference it in the RCA Matrix's Layer 4 Verdict.
