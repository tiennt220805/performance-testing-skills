# Spike Test Profile (Burst Resilience & Recovery)

**Note:** Route paths, field names, and payloads in this file's examples (`/api/cart`, `productId`, etc.) illustrate the EShop reference scenario only — substitute the actual `In-Scope Routes`/fields from the target project's `PERF_SPEC.md`; only the JS patterns (executor configurations, threshold structures, JIT loading rules) are mandatory to preserve.

Loaded by BUILD's JIT Protocol only when `PERF_SPEC.md`'s `Declared Test Strategy` metadata explicitly includes `Spike`.

## 1. Goal: Burst Resilience & Recovery, Not Steady Capacity

A Spike test simulates a sudden traffic surge a Load test's smooth ramp never exercises — a flash sale, a viral link, a cron-triggered batch job hitting an API all at once. Two distinct things are being measured: (a) does the SUT survive the surge without cascading failure, and (b) does it **recover** to baseline latency once the surge subsides.

## 2. Executor Selection: Closed System vs. Open System

- **Closed System → `ramping-vus` (default).** Models a real user/browser/mobile client: each VU waits for a response before issuing its next request. Arrival rate is throttled by whatever the SUT can actually process — the correct model for most web/mobile spike scenarios (a real crowd hitting the site during a flash sale).
- **Open System → `ramping-arrival-rate`.** Models a traffic source with a fixed request rate independent of the SUT's processing speed — an API Gateway forwarding external calls, a webhook fan-in, an IoT device fleet reporting on a fixed schedule. Under this executor, if the SUT falls behind, k6 keeps issuing requests at the declared rate regardless, and the resulting backlog/queueing is itself the signal under test.
- **Selection rule.** Default to `ramping-vus` unless `PERF_SPEC.md`'s `Target SUT Stack`/`In-Scope Routes` metadata identifies the traffic source as something that does not wait for a response before sending the next one (an internal service-to-service API, a webhook receiver, an IoT ingestion endpoint). Choosing the wrong executor for the real traffic shape produces telemetry that doesn't represent the actual failure mode being investigated.
- See `references/queueing-theory-mmc.md` (repo root) for the underlying open-vs-closed-system queueing math (M/M/c) explaining why these two executors produce fundamentally different load characteristics against the same nominal target rate.

```javascript
// Closed system: ramping-vus
scenarios: {
  spike: {
    executor: 'ramping-vus',
    startVUs: {{PERF_PLAN_BASELINE_VUS}},
    stages: [
      { duration: '{{PERF_PLAN_PRE_SPIKE_BASELINE_DURATION}}', target: {{PERF_PLAN_BASELINE_VUS}} }, // holds FLAT at baseline — not a ramp — establishing the pre-spike measurement window `preSpikeLatency` reads from in §4
      { duration: '{{PERF_PLAN_SPIKE_RAMP_DURATION}}', target: {{PERF_PLAN_PEAK_VUS}} },  // sourced from PERF_PLAN.md Per-Strategy Workload Boundaries, row "Spike"
      { duration: '{{PERF_PLAN_HOLD_AT_PEAK_DURATION}}', target: {{PERF_PLAN_PEAK_VUS}} },
      { duration: '{{PERF_PLAN_RAMP_DOWN_DURATION}}', target: {{PERF_PLAN_BASELINE_VUS}} }, // post-spike recovery window — see §4
    ],
  },
},
```

```javascript
// Open system: ramping-arrival-rate
scenarios: {
  spike_open_system: {
    executor: 'ramping-arrival-rate',
    startRate: {{PERF_PLAN_BASELINE_RPS}},
    timeUnit: '1s',
    preAllocatedVUs: {{PERF_PLAN_PREALLOCATED_VUS}}, // sized generously — this executor spawns VUs as needed to sustain the arrival rate regardless of response latency
    maxVUs: {{PERF_PLAN_MAX_VUS}},
    stages: [
      { duration: '{{PERF_PLAN_SPIKE_RAMP_DURATION}}', target: {{PERF_PLAN_PEAK_RPS}} },  // sourced from PERF_PLAN.md, row "Spike"
      { duration: '{{PERF_PLAN_HOLD_AT_PEAK_DURATION}}', target: {{PERF_PLAN_PEAK_RPS}} },
      { duration: '{{PERF_PLAN_RAMP_DOWN_DURATION}}', target: {{PERF_PLAN_BASELINE_RPS}} },
    ],
  },
},
```

## 3. Threshold Sourcing — Per-Endpoint SLO Ceilings

Same rule as every other profile: every `thresholds` entry maps 1:1 to a row in `PERF_SPEC.md`'s SLO matrix — never a hardcoded figure presented as a default.

## 4. Recovery Threshold — Internal Engineering Heuristic

Unlike the per-endpoint SLO ceilings above (external, business-facing, sourced from `PERF_SPEC.md`), the **recovery check** is an internal engineering heuristic verifying the SUT returns to baseline behavior after the spike subsides — analogous to PLAN's idle-CPU `< 5%` check, not itself a row in `PERF_SPEC.md`. Implement it by tagging requests with a phase label and recording separate `Trend` metrics for the pre-spike and post-spike windows, then comparing their percentiles:

```javascript
import { Trend } from 'k6/metrics';

const preSpikeLatency = new Trend('latency_pre_spike');
const postSpikeLatency = new Trend('latency_post_spike');

export default function () {
  const res = http.get(`${__ENV.BASE_URL}/api/search?q=shoes`, authHeaders);
  const phase = getCurrentStagePhase(); // 'pre-spike' | 'peak' | 'post-spike', derived from elapsed test time
  if (phase === 'pre-spike') preSpikeLatency.add(res.timings.duration);
  if (phase === 'post-spike') postSpikeLatency.add(res.timings.duration);
}
```

**Internal default:** flag "failed to recover" if post-spike p95 does not return to within 10% of pre-spike p95 by the end of the ramp-down window. This 10% figure is an internal engineering heuristic — state it explicitly as such in any report referencing it; never present it as a `PERF_SPEC.md`-sourced SLO.

## 5. Common Pitfalls

- Defaulting to `ramping-arrival-rate` without confirming the SUT's real traffic source is actually an open system — this can generate more effective load than intended if the real-world clients would have backed off (closed-system behavior) but the script doesn't.
- Presenting the recovery-threshold percentage as if it were stakeholder-confirmed — it must be labeled an internal engineering heuristic wherever it appears in a draft or report.
- Omitting the post-spike hold-at-baseline stage entirely (ramping straight to 0) — without a stable post-spike window, there's no data to measure recovery against.
