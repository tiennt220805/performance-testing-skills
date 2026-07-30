# Soak Test Profile (Endurance / Memory Leak Check)

**Note:** Route paths, field names, and payloads in this file's examples (`/api/cart`, `productId`, etc.) illustrate the EShop reference scenario only — substitute the actual `In-Scope Routes`/fields from the target project's `PERF_SPEC.md`; only the JS patterns (executor configurations, threshold structures, JIT loading rules) are mandatory to preserve.

Loaded by BUILD's JIT Protocol only when `PERF_SPEC.md`'s `Declared Test Strategy` metadata explicitly includes `Soak`.

## 1. Goal: Endurance & Time-Dependent Degradation, Not Peak Capacity

A Soak test runs at a sustained, *moderate* load — never peak — for an extended duration specifically to catch failure modes that only manifest over time: memory leaks, unbounded in-memory cache growth, connection pool exhaustion, gradual DB fragmentation, or disk/log fill. A short high-VU run cannot surface any of these; only sustained elapsed time can.

## 2. Executor Configuration — Sustained Moderate Load

Use `constant-vus` (or a brief ramp followed by a flat hold) at roughly **70–80% of the `Load (baseline)` strategy's target VUs** — never spike-level peak — for a long duration (typically 1h–4h+), sourced from `PERF_PLAN.md`'s Per-Strategy Workload Boundaries row for `Soak`, never invented independently:

```javascript
scenarios: {
  soak: {
    executor: 'constant-vus',
    vus: {{PERF_PLAN_SOAK_TARGET_VUS}},     // sourced from PERF_PLAN.md, row "Soak" — typically ~70-80% of Load (baseline) VUs, never invented independently
    duration: '{{PERF_PLAN_SOAK_DURATION}}', // e.g. "2h", sourced from PERF_PLAN.md
  },
},
```

A run this long will almost certainly outlive a normal auth token's TTL — the expiry-gated token refresh logic in `correlation.md` §5 is **mandatory** for Soak scripts, not merely optional as it is for the other three strategies.

## 3. Threshold Sourcing — Per-Endpoint SLO Ceilings

Same standard rule as every other profile: every `thresholds` entry maps 1:1 to a row in `PERF_SPEC.md`'s SLO matrix — never a hardcoded figure presented as a default.

## 4. Time-Windowed Degradation Metrics — Mandatory

A single flat threshold applied across an entire multi-hour run cannot catch "fast at minute 5, slow at hour 3" — that signature is exactly what Soak exists to find, and it is invisible to one aggregate p95 covering the whole run. Metrics **must** be bucketed by time window (e.g. the first 15 minutes vs. the last 15 minutes) rather than relying on a single run-wide percentile:

```javascript
import { Trend } from 'k6/metrics';

const earlyWindowLatency = new Trend('latency_early_window');
const lateWindowLatency = new Trend('latency_late_window');

const SOAK_DURATION_SECONDS = {{PERF_PLAN_SOAK_DURATION_SECONDS}}; // sourced from PERF_PLAN.md
const WINDOW_SECONDS = 15 * 60; // 15-minute comparison window — internal engineering heuristic, not a PERF_SPEC.md value

// setup() runs exactly once, before any VU starts iterating, and its return value is passed as
// `data` into every default-function invocation across every VU. This is the correct k6 pattern
// for a single run-wide timestamp — __ENV is fixed at CLI-invocation time (before k6 actually
// starts executing), so __ENV.TEST_START_MS would be undefined and produce a NaN elapsed-time
// calculation; setup() captures the real moment execution begins instead.
export function setup() {
  return { testStartMs: Date.now() };
}

export default function (data) {
  const elapsedSeconds = (Date.now() - data.testStartMs) / 1000;
  const res = http.get(`${__ENV.BASE_URL}/api/search?q=shoes`, authHeaders);

  if (elapsedSeconds <= WINDOW_SECONDS) {
    earlyWindowLatency.add(res.timings.duration);
  } else if (elapsedSeconds >= SOAK_DURATION_SECONDS - WINDOW_SECONDS) {
    lateWindowLatency.add(res.timings.duration);
  }
}
```

The comparison of `earlyWindowLatency` vs. `lateWindowLatency` percentiles at report time (in the k6 summary or a custom `handleSummary()`) is what actually detects degradation — never a single-pass aggregate threshold.

## 5. Degradation Heuristic — Internal Engineering Threshold

The trigger for flagging degradation is an **internal engineering heuristic**, not a `PERF_SPEC.md` SLO — analogous to PLAN's idle-CPU `< 5%` check: e.g., late-window p95 degrading **> 20%** versus early-window p95, or SUT-side RSS/memory climbing monotonically without plateauing across the run. State this 20% figure explicitly as a process heuristic wherever it's cited in a report — never present it as a business-facing SLO.

## 6. Feeding AUDIT's Layer 2 / Layer 3 RCA

The early-window vs. late-window comparison, together with any SUT-side RSS/CPU trend captured alongside it (see `test-environment-and-baseline/SKILL.md` for capturing SUT-side resource metrics during a run), is the direct evidence AUDIT's 4-layer RCA needs to distinguish "always slow" (a design/config problem, visible in any window) from "gets slow over time" (a leak/exhaustion problem, only visible in the late window) — most often surfacing at Layer 2 (Application Runtime — unbounded cache/leak) or Layer 3 (Data — connection pool exhaustion, fragmentation). Never let a Soak report collapse this time-dependent evidence into one flat aggregate number.
