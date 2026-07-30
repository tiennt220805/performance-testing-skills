# Load Test Profile (Steady-State Baseline)

**Note:** Route paths, field names, and payloads in this file's examples (`/api/cart`, `productId`, etc.) illustrate the EShop reference scenario only — substitute the actual `In-Scope Routes`/fields from the target project's `PERF_SPEC.md`; only the JS patterns (executor configurations, threshold structures, JIT loading rules) are mandatory to preserve.

Loaded by BUILD's JIT Protocol only when `PERF_SPEC.md`'s `Declared Test Strategy` metadata explicitly includes `Load`.

## 1. Goal: Steady-State Capacity, Not a Breaking Point

Confirms the SUT sustains expected production-level traffic within its declared SLOs for a realistic duration. This is distinct from Stress (finding where the system breaks) and Spike (surviving and recovering from a sudden burst) — Load validates behavior at a *known, agreed* traffic level, not an unknown limit.

## 2. Executor Selection

- **`ramping-vus` (default).** A 3-stage shape — ramp up, hold at target, ramp down — mirrors how real traffic actually arrives (users don't appear instantaneously) and the ramp-down phase gives a clean window for comparing post-load behavior against the held-load window.
- **`constant-vus` (only when the boundary states a flat count with no ramp).** If `PERF_PLAN.md`'s workload boundary for this strategy describes a flat VU count with no stated ramp shape, hold that VU count constant for the full duration from `t=0` instead of synthesizing a ramp that wasn't specified.

```javascript
export const options = {
  scenarios: {
    load_baseline: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '{{PERF_PLAN_RAMP_UP_DURATION}}', target: {{PERF_PLAN_TARGET_VUS}} },  // sourced from PERF_PLAN.md Per-Strategy Workload Boundaries, row "Load (baseline)"
        { duration: '{{PERF_PLAN_HOLD_DURATION}}', target: {{PERF_PLAN_TARGET_VUS}} },
        { duration: '{{PERF_PLAN_RAMP_DOWN_DURATION}}', target: 0 },
      ],
    },
  },
  thresholds: {
    'http_req_duration{group:::search}': ['p(95)<{{PERF_SPEC_P95_MS_SEARCH}}'],     // sourced directly from PERF_SPEC.md SLO matrix
    'http_req_duration{group:::cart}': ['p(95)<{{PERF_SPEC_P95_MS_CART}}'],         // sourced directly from PERF_SPEC.md SLO matrix
    'http_req_duration{group:::checkout}': ['p(95)<{{PERF_SPEC_P95_MS_CHECKOUT}}'], // sourced directly from PERF_SPEC.md SLO matrix
    http_req_failed: ['rate<{{PERF_SPEC_MAX_FAIL_RATE}}'],                          // sourced directly from PERF_SPEC.md SLO matrix
  },
};
```

## 3. Mapping Workload Boundaries — Never Invent VU Counts

`target`, ramp durations, and hold duration are pulled directly from the `Load (baseline)` row of `PERF_PLAN.md`'s Per-Strategy Workload Boundaries table — never chosen independently at BUILD time. If that row is missing bounds for this strategy, that is a PLAN-phase gap: stop and require `/perf-plan` to be completed for this strategy before generating the script, rather than guessing a VU count.

## 4. Threshold Sourcing — Per-Endpoint SLO Ceilings, Never Hardcoded

Every `thresholds` entry is a **per-endpoint SLO ceiling** and must be traceable 1:1 to a specific row in `PERF_SPEC.md`'s Target SLO & Metric Baseline Matrix — represented above as a `{{PERF_SPEC_...}}` placeholder, or, once resolved, accompanied by a comment stating `// sourced directly from PERF_SPEC.md SLO matrix`. Never substitute a number that "looks reasonable" (e.g. a bare `400ms` or `1.0%`) as if it were a system default — if `PERF_SPEC.md` itself sourced a figure from `references/slo-cheatsheet.md` because the stakeholder didn't specify one, that provenance carries through into the script's threshold, it does not get re-invented here.

## 5. Common Pitfalls

- Treating "Load test" as license to pick an arbitrarily small VU count instead of `PERF_PLAN.md`'s actual declared target.
- Skipping the ramp-down stage — it provides the clean post-load window later comparisons (e.g. a Spike profile's recovery check) rely on.
- Hardcoding a threshold value instead of sourcing it from `PERF_SPEC.md`, even when the hardcoded number happens to match.
