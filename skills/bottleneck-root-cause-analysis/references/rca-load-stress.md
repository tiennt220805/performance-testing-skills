# Strategy Audit Matrix: Load & Stress

**Note:** Metrics and scenario examples in this file illustrate the EShop reference scenario only — substitute the actual metrics/routes from the target project's `PERF_SPEC.md`; only the diagnostic matrix and 4-layer decision logic are mandatory to preserve.

Loaded conditionally by AUDIT's JIT Protocol during Step 3 — exactly ONE of the three Strategy Audit Matrix files (`rca-load-stress.md` / `rca-spike.md` / `rca-soak.md`) is loaded, matching the `Declared Test Strategy` under audit for this run; the other two are left unread, even for a multi-strategy engagement (each strategy's AUDIT pass loads only its own matrix). This is the opposite of the four layer files, which are always loaded together in full regardless of strategy.

## Scope

This file is an **overlay**, not a re-explanation of the 4-layer diagnostic mechanics already covered in `rca-layer1-transport.md` → `rca-layer4-infrastructure.md`. It only states which layer to check first for a Load- or Stress-specific symptom, and the strategy-specific thresholds unique to each. **Load and Stress are two separate logic streams inside this one file — never merge their pass/fail criteria.** Load confirms a *known* steady-state SLO; Stress has no known target and exists to *find* an unknown breaking point. Load has no breaking-point detection; Stress has no steady-state SLO check in the Load sense.

## Diagnostic Matrix

| Strategy | Symptom | Primary Layer to Check First |
|---|---|---|
| Load | RPS plateaus below the `PERF_SPEC.md` target despite the VU ramp fully reaching its held level | Layer 3 (DB pool/lock contention) or Layer 4 (CPU/`iowait` ceiling) — check whichever correlates in time |
| Load | Latency creeps upward across the hold window even though VU count is flat | Layer 2 — an early leak signature; flag it even though Load isn't Soak's dedicated leak-hunting strategy. Visible degradation even at Load's shorter duration is a *stronger* signal than a Soak-only finding, not a weaker one |
| Stress | RPS flatlines (or drops) while the escalation ladder continues to the next step | Layer 3/4 — the SUT has saturated a hard resource ceiling; adding more VUs no longer buys throughput |
| Stress | Latency jump between two consecutive escalation steps is sharply non-linear | Layer 2 (thread-pool/event-loop exhaustion) or Layer 3 (lock-contention onset) — the p99 3x-jump heuristic below pinpoints exactly which step |
| Stress | Error Rate crosses the sustained breaking-point threshold | Whichever layer's error signature dominates the raw log at that step (`SQLITE_BUSY` → Layer 3, `5xx` → Layer 2/3, connection resets → Layer 1) |

## Strategy-Specific Threshold Logic

**Load** has no breaking-point heuristic of its own — its only pass/fail criterion is the per-endpoint SLO comparison already defined in `SKILL.md`'s Required Output Format (RPS/p95/error-rate vs. `PERF_SPEC.md`). This layer overlay exists only to say *where to look* once a Load SLO row shows `FAIL`.

**Stress** reuses `profile-stress-test.md` §4's breaking-point heuristics verbatim — never redefine them here:
- **Sustained Error Rate > 5%** over a rolling window → flag the currently-held VU step as the breaking point.
- **p99 latency exceeding ~3x its value at the previous escalation step** → tracked via the same per-step `stepLatency` object (`stepLatency[currentStepVUs]` compared against `stepLatency[previousStep]`) defined in `profile-stress-test.md` §4 — do not build a separate tracking mechanism here.
- If `PERF_PLAN.md` declared a custom escalation ladder for Stress rather than the 50→100→200→400→800 exploratory default, read `stepLatency`'s keys from that custom ladder's actual VU values, per `profile-stress-test.md`'s own note.

## Worked Example

**Load:**

```text
perf-test/logs/baseline-audit.log summary:
  http_reqs...........: 14,820   RPS=49.4  (target: 50 RPS)
  http_req_duration...: p95=610ms          (target: 400ms)
  http_req_failed.....: 0.3%               (target: <1.0%)

Layer 3 check: DB pool at 18/20 connections busy at peak — near saturation, not exhausted.
```

RPS is within 1.2% of target (acceptable), but p95 breaches its 400ms SLO by 52%. The pool being busy-but-not-exhausted rules out outright exhaustion as the sole cause; correlate against Layer 3's query-level evidence before concluding root cause. This is a Load SLO breach — there is no VU escalation involved, so it is never framed as a "breaking point."

**Stress:**

```text
Escalation ladder: 50 -> 100 -> 200 -> 400 -> 800 VU (ASSUMED — exploratory default; PERF_PLAN.md declared no custom ladder)

stepLatency p99 by step:  50 VU: 210ms | 100 VU: 240ms | 200 VU: 310ms | 400 VU: 1,850ms (5.97x jump)
Error Rate at 400 VU step: 7.8% sustained over 45s (> 5% threshold)
800 VU step: not reached — ladder halted once the 400 VU step tripped both heuristics.
```

Breaking point identified at 400 VU: both heuristics (p99 3x-jump and sustained >5% error rate) trip at the same step, corroborating each other. AUDIT does not extrapolate what would happen at 800 VU — the ladder simply wasn't completed (Non-Negotiable 5, Reject Flawed Logic).

**Stress — breaking point not found within the tested range:**

```text
stepLatency p99 by step:  50 VU: 195ms | 100 VU: 220ms | 200 VU: 265ms | 400 VU: 310ms | 800 VU: 410ms
Error Rate at every step: stayed below 1.0% throughout, no sustained breach of the 5% threshold.
```

No step tripped either heuristic — the ladder completed all 5 steps cleanly. **Do not report a "breaking point" here, and do not extrapolate one past 800 VU** ("it would probably break around 1,500 VU" is exactly the flawed-logic pattern Non-Negotiable 5 forbids). Report explicitly that the breaking point was **not found within the tested range**, and — if a higher ceiling matters to the stakeholder — recommend a follow-up Stress run with an extended ladder, rather than guessing at the untested number now.

## Feeding the RCA Matrix

For Load, a SLO breach reduces directly to the existing Full Load Telemetry Table row format already defined in `SKILL.md` — no new format needed; this file only tells you which layer to check when that row shows `FAIL`. For Stress, the breaking point itself becomes the headline `Evidence` line for whichever layer's evidence explains *why* that VU count broke the system — e.g. `Evidence: Breaking point at {{VU_COUNT}} VU — p99 jumped {{MULTIPLIER}}x from the prior step, Error Rate {{ERROR_RATE}}% sustained; SQLITE_BUSY x{{COUNT}} concurrent with onset` / `Verdict: Root cause — write-path lock contention at {{VU_COUNT}}+ VU (Layer 3)`. Map every `SQLITE_BUSY`/`5xx`/connection-reset signature found at the breaking-point step into the Error Signature Distribution table exactly as `rca-layer1-transport.md`/`rca-layer3-data.md` already define per signature type.
