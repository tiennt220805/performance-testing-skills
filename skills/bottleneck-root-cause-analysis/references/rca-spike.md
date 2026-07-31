# Strategy Audit Matrix: Spike

**Note:** Metrics and scenario examples in this file illustrate the EShop reference scenario only — substitute the actual metrics/routes from the target project's `PERF_SPEC.md`; only the diagnostic matrix and 4-layer decision logic are mandatory to preserve.

Loaded conditionally by AUDIT's JIT Protocol during Step 3 — exactly ONE of the three Strategy Audit Matrix files (`rca-load-stress.md` / `rca-spike.md` / `rca-soak.md`) is loaded, matching the `Declared Test Strategy` under audit for this run; the other two are left unread, even for a multi-strategy engagement (each strategy's AUDIT pass loads only its own matrix). This is the opposite of the four layer files, which are always loaded together in full regardless of strategy.

## Scope

An **overlay** on `rca-layer1-transport.md` → `rca-layer4-infrastructure.md` — it does not re-explain how to read `vmstat`/GC logs/etc. Spike AUDIT diagnoses two things (per `profile-spike-test.md` §1): does the SUT survive the burst without cascading failure, and does it **recover** to baseline latency once the burst subsides.

## Diagnostic Matrix

| Symptom | Primary Layer to Check First | Why |
|---|---|---|
| `http_req_blocked` spikes sharply during ramp-to-peak, closed-system (`ramping-vus`) executor | Layer 1 — Transport | Closed-system backpressure: VUs queue waiting for a response before issuing the next request. This is expected client-side throttling, not necessarily a SUT defect — run `rca-layer1-transport.md`'s load-generator-vs-SUT test before concluding anything |
| Backlog/queue depth grows steadily during ramp-to-peak, open-system (`ramping-arrival-rate`) executor | Layer 2/3 — Application/Data | Under an open system the arrival rate is fixed regardless of SUT capacity — a growing backlog is a genuine SUT-side saturation signal, not client throttling. Confirms this was the correct executor choice per `profile-spike-test.md` §2's selection rule |
| Latency does not return to pre-spike baseline during the ramp-down/hold-at-baseline stage | Layer 3 — Data (most common), sometimes Layer 2 | A SUT that recovers immediately in CPU/thread terms but stays slow past the spike's end is frequently held by a lock/queue that doesn't self-clear — see the write-path linkage below |
| Error Rate spikes only during the hold-at-peak stage and drops immediately once VUs ramp down | Not necessarily any layer's root cause | Transient overload at peak that clears on its own is expected Spike behavior, not evidence of a persistent defect — distinguish this from the recovery-failure case above |

## Strategy-Specific Threshold Logic

Reuses `profile-spike-test.md` §4's recovery-check mechanism verbatim — never redefine it: the `preSpikeLatency`/`postSpikeLatency` `Trend` metrics, compared as post-spike p95 vs. pre-spike p95. **Internal heuristic: "failed to recover" is post-spike p95 not returning within 10% of pre-spike p95 by the end of the ramp-down window** — this 10% figure is sourced from `profile-spike-test.md`, not redefined here.

**Persistent post-spike lock contention — the Spike-specific distinguishing case:** when recovery fails (per the 10% heuristic above) *and* the raw log shows `SQLITE_BUSY`/write-path errors continuing into the post-spike window (not just during the peak), this points specifically at Layer 3 — the burst created write contention that hasn't cleared because queued writes are still draining. This differs from a Layer 2 finding (e.g. GC still catching up, thread pool still recovering) — use `rca-layer3-data.md`'s read-path/write-path distinction to tell them apart before attributing recovery failure to either.

## Worked Example

```text
preSpikeLatency (pre-spike window): p95=180ms
postSpikeLatency (post-spike window, measured through ramp-down): p95=410ms

Recovery check: 410ms is 128% above the 180ms pre-spike baseline — far outside the 10% recovery threshold.

Raw log excerpt, post-spike window only:
  SQLITE_BUSY: database is locked  (x22 occurrences, all timestamped AFTER the peak-hold stage ended)
```

The 22 `SQLITE_BUSY` occurrences are not concentrated during the peak (where contention would be expected) but *after* it — writes queued during the burst are still draining and colliding with new traffic in the ramp-down window. **Verdict: Layer 3, write-path lock contention outlasting the spike itself** — a persistent backlog, not a transient overload.

**Clean recovery — contrast case:**

```text
preSpikeLatency (pre-spike window): p95=175ms
postSpikeLatency (post-spike window, measured through ramp-down): p95=188ms

Recovery check: 188ms is 7.4% above the 175ms pre-spike baseline — within the 10% recovery threshold.

Raw log excerpt, post-spike window: no SQLITE_BUSY, no 5xx, error rate flat at 0.1% throughout.
```

Recovery check passes cleanly, and no error signature carries over into the post-spike window. **Verdict: No signal at this layer** for the recovery check — the SUT absorbed the burst and returned to baseline as designed. This is the expected outcome for a well-provisioned SUT and should be reported as plainly as a failure would be, not treated as "nothing to say."

## Feeding the RCA Matrix

The recovery check becomes the report's explicit recovery verdict against the 10% heuristic — state it plainly, e.g. `Recovery: FAILED — post-spike p95 {{POST_SPIKE_P95}}ms vs. pre-spike p95 {{PRE_SPIKE_P95}}ms baseline ({{PERCENT}}% above the 10% threshold)` — and feeds the same `Evidence`/`Verdict` row format as any other layer finding, e.g. `Evidence: Recovery failed ({{PERCENT}}% above threshold); SQLITE_BUSY x{{COUNT}} confined to the post-spike window` / `Verdict: Root cause — write-path lock contention persisting past spike end (Layer 3)`. Map the `SQLITE_BUSY` count into the Error Signature Distribution table's existing row exactly as `rca-layer3-data.md` defines.
