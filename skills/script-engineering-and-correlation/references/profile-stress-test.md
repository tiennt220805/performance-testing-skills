# Stress Test Profile (Breaking Point Discovery)

**Note:** Route paths, field names, and payloads in this file's examples (`/api/cart`, `productId`, etc.) illustrate the EShop reference scenario only — substitute the actual `In-Scope Routes`/fields from the target project's `PERF_SPEC.md`; only the JS patterns (executor configurations, threshold structures, JIT loading rules) are mandatory to preserve.

Loaded by BUILD's JIT Protocol only when `PERF_SPEC.md`'s `Declared Test Strategy` metadata explicitly includes `Stress`.

## 1. Goal: Find the Breaking Point, Not Validate a Known Capacity

Stress differs fundamentally from Load and Spike: those validate behavior at a *known, agreed* traffic level. Stress exists precisely because the breaking point is **not** known in advance — the executor must escalate load progressively until a failure criterion trips, rather than run a single fixed profile for a fixed duration.

## 2. Escalation Ladder Sourcing

- **If `PERF_PLAN.md`'s Per-Strategy Workload Boundaries table declares an explicit VU ceiling or escalation ladder for the `Stress` row, use exactly that ladder** — do not substitute a different one.
- **If it does not**, use an exploratory default escalation ladder and label it explicitly `ASSUMED — exploratory default` in every draft/report that references it (Non-Negotiable 4, Surface Assumptions): doubling steps such as 50 → 100 → 200 → 400 → 800 VU, each held long enough to reach steady-state readings (e.g. 3–5 minutes) before escalating to the next step.
- Never pick an escalation ladder silently — its source (`PERF_PLAN.md`-confirmed vs. `ASSUMED`) must be stated explicitly.

## 3. Executor Configuration

`ramping-vus` with one stage per escalation step. The run's actual endpoint is not a fixed clock time — it's whichever step trips the breaking-point detection in §4:

```javascript
scenarios: {
  stress_escalation: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { duration: '{{DWELL_DURATION}}', target: 50 },   // Step 1 — ASSUMED, exploratory default unless PERF_PLAN.md states an explicit ladder
      { duration: '{{DWELL_DURATION}}', target: 100 },  // Step 2
      { duration: '{{DWELL_DURATION}}', target: 200 },  // Step 3
      { duration: '{{DWELL_DURATION}}', target: 400 },  // Step 4
      { duration: '{{DWELL_DURATION}}', target: 800 },  // Step 5
    ],
  },
},
```

## 4. Breaking Point Detection — Internal Engineering Heuristic Thresholds

Distinct from the per-endpoint SLO ceilings sourced from `PERF_SPEC.md`, these thresholds exist to **detect and flag the breaking point itself** — an internal engineering heuristic, analogous to PLAN's idle-CPU `< 5%` check:

- **Sustained Error Rate > 5%** over a rolling window (e.g. 30s) → flag the currently-held VU step as the breaking point.
- **p99 latency exploding beyond ~3x its value at the previous escalation step** → flag degradation onset even before error rate crosses 5%, since latency blow-up frequently precedes outright request failures.

`options.thresholds` should carry **both** the breaking-point heuristic and the ordinary per-endpoint SLO ceilings from `PERF_SPEC.md`, run side by side. This lets a report show precisely which step first breached the *business* SLO — a much earlier and often more actionable signal — versus which step actually broke the system outright:

```javascript
thresholds: {
  // Breaking-point heuristic — internal engineering default, NOT a PERF_SPEC.md SLO ceiling.
  // abortOnFail: false — deliberately does NOT stop the run on breach. The goal of Stress is to
  // observe behavior *beyond* the breaking point (does it degrade gracefully or cascade to total
  // failure?), so escalation continues through the remaining ladder steps; aborting early would
  // throw away exactly the data this strategy exists to collect.
  http_req_failed: [{ threshold: 'rate<0.05', abortOnFail: false }],

  // Per-endpoint SLO ceilings — sourced directly from PERF_SPEC.md SLO matrix, run in parallel so the
  // report can show which step first breached the business SLO, distinct from the step that broke the system.
  'http_req_duration{group:::search}': ['p(95)<{{PERF_SPEC_P95_MS_SEARCH}}'],
  'http_req_duration{group:::checkout}': ['p(95)<{{PERF_SPEC_P95_MS_CHECKOUT}}'],
},
```

Tag each request with its current escalation step (e.g. via a custom `Counter`/`Trend` keyed by VU-target-at-time-of-request) so the exact step at which either signal tripped can be identified precisely, rather than inferred after the fact from an aggregate summary. The p99-blow-up signal specifically needs a **per-step** `Trend` so the current step's p99 can be compared against the *previous* step's, not against the run-wide aggregate:

```javascript
import { Trend } from 'k6/metrics';

// One Trend per escalation step lets step N's p99 be compared against step N-1's p99 directly.
// The keys above match the default exploratory ladder; if PERF_PLAN.md declares a custom ladder,
// build this object dynamically from that ladder's actual VU values instead of copying these literal keys.
const stepLatency = {
  50: new Trend('latency_step_50vu'),
  100: new Trend('latency_step_100vu'),
  200: new Trend('latency_step_200vu'),
  400: new Trend('latency_step_400vu'),
  800: new Trend('latency_step_800vu'),
};

export default function () {
  const currentStepVUs = getCurrentEscalationStepTarget(); // derived from elapsed test time vs. the stages array above
  const res = http.get(`${__ENV.BASE_URL}/api/search?q=shoes`, authHeaders);
  stepLatency[currentStepVUs].add(res.timings.duration);
  // Compare stepLatency[currentStepVUs].p99 against stepLatency[previousStep].p99 in handleSummary()
  // or a post-run analysis pass — a >3x jump between consecutive steps flags degradation onset.
}
```

## 5. Reporting the Breaking Point for AUDIT

The exact VU count and elapsed step at which the heuristic tripped is what gets recorded and handed to AUDIT as the measured breaking point — never estimated, rounded, or extrapolated past whatever step was actually reached. If the ladder runs out (e.g. all 5 steps complete with no breach), report that the breaking point was **not found within the tested range** — do not linearly project where it "would probably" occur beyond the last tested step (Non-Negotiable 5, Reject Flawed Logic).

## 6. Common Pitfalls

- Running Stress with a single fixed VU target like a Load test — this defeats the purpose, which requires progressive escalation to actually find a limit.
- Conflating the 5% error-rate breaking-point heuristic with the Max Fail Rate % SLO from `PERF_SPEC.md` — they are different thresholds serving different purposes and must not be reported as the same number.
- Omitting the `ASSUMED — exploratory default` label when `PERF_PLAN.md` doesn't declare an explicit escalation ladder.
