# Queueing Theory Foundations (M/M/c) and Workload Modeling

**Note:** Numerical scenarios in this file illustrate theoretical queueing dynamics using the EShop reference numbers only — substitute the actual target RPS/latency numbers from the target project's `PERF_SPEC.md`; the mathematical formulas, queueing principles, and k6 executor selection criteria are mandatory to preserve.

**This file is an estimation tool, not a source of measured truth.** Every number this file's formulas produce (a predicted VU count, a predicted saturation point) is a theoretical estimate for planning purposes only — never a measured fact. It may seed a starting VU count for Load's ramp target or Stress's first escalation step, but the figure actually recorded in `PERF_PLAN.md`'s Per-Strategy Workload Boundaries, and any conclusion about where a system actually breaks, must always come from a real k6 run's measured data (Non-Negotiable 1, Never Assume Latency). Presenting this file's calculated output as if it were observed behavior is exactly the kind of unmeasured claim this suite exists to eliminate.

## 1. Fundamental Laws of Queueing

**Little's Law:**

$$L = \lambda \cdot W$$

- $L$ — the mean number of requests/VUs concurrently in the system, i.e. $N_{\text{VUs}}$.
- $\lambda$ — throughput, the mean arrival/completion rate (RPS).
- $W$ — mean total time a request spends in the system: response time plus any per-VU think time between iterations, in seconds.

**System Utilization:**

$$\rho = \frac{\lambda}{c \cdot \mu}$$

- $\rho$ — utilization, a fraction from 0 (idle) to 1 (fully saturated).
- $c$ — the number of parallel servers/workers/threads capable of processing requests concurrently.
- $\mu$ — service rate per server: requests one worker can complete per second.

**`c` is not invented — it is sourced from `PERF_PLAN.md`'s Environment Parity Summary Architecture Limits** (e.g. $c \approx 1$ for a single-process Node.js event loop's CPU-bound work, or $c$ = the configured connection-pool size for a pooled JVM service). If `PERF_PLAN.md` doesn't record this yet, that is a PLAN-phase gap to fill, not something this file should guess.

## 2. The Exponential Latency Knee ($\rho \to 1$)

For a simple single-queue model, mean queueing delay grows approximately as:

$$W_q \propto \frac{\rho}{1 - \rho}$$

As $\rho$ approaches 1, the denominator $(1-\rho)$ approaches 0 and $W_q$ diverges toward infinity — latency does not degrade linearly as load increases, it explodes nonlinearly once utilization crosses roughly the 80%–90% range. This is why a system can look nearly fine at 70% utilization and fall apart within a small additional load increment.

**Model limitation, stated explicitly:** this $\frac{\rho}{1-\rho}$ shape is the intuitive approximation from the single-server M/M/1 case, not the exact Erlang-C solution for a true M/M/c multi-server queue. It exists here to build intuition for *why* a knee exists — it is not a precision tool for predicting the exact VU count at which a specific real system will break.

**This is the exact mathematical shape behind `rca-load-stress.md`'s p99-jump breaking-point heuristic** — a >3x latency jump between two consecutive Stress escalation steps (`profile-stress-test.md` §4) is what this exponential curve looks like in a real raw log. The theory here explains *why* that heuristic works; it does not replace the requirement to actually measure it.

## 3. Open System vs. Closed System Models

- **Closed System (VU-centric).** A fixed population of $N$ virtual users; each VU issues its next request only after receiving the previous response (plus any think time). Throughput is an *emergent* property, self-throttled by how fast the SUT actually responds — arrival rate can never exceed what the SUT is currently capable of returning.
- **Open System (Throughput-centric).** Requests arrive as an independent stream at a rate $\lambda$ set externally, with no feedback from the SUT's response speed. If $\lambda$ exceeds $c \cdot \mu$ (i.e. $\rho > 1$), the theoretical queue grows without bound — arrivals simply keep coming regardless of whether the SUT can keep up.

The practical executor-selection rule for these two models is already codified in `profile-spike-test.md` §2 and is not restated differently here — quoted verbatim:

> **Closed System → `ramping-vus` (default).** Models a real user/browser/mobile client: each VU waits for a response before issuing its next request. Arrival rate is throttled by whatever the SUT can actually process — the correct model for most web/mobile spike scenarios (a real crowd hitting the site during a flash sale).
>
> **Open System → `ramping-arrival-rate`.** Models a traffic source with a fixed request rate independent of the SUT's processing speed — an API Gateway forwarding external calls, a webhook fan-in, an IoT device fleet reporting on a fixed schedule. Under this executor, if the SUT falls behind, k6 keeps issuing requests at the declared rate regardless, and the resulting backlog/queueing is itself the signal under test.
>
> **Selection rule.** Default to `ramping-vus` unless `PERF_SPEC.md`'s `Target SUT Stack`/`In-Scope Routes` metadata identifies the traffic source as something that does not wait for a response before sending the next one (an internal service-to-service API, a webhook receiver, an IoT ingestion endpoint). Choosing the wrong executor for the real traffic shape produces telemetry that doesn't represent the actual failure mode being investigated.

This section supplies the underlying math for why these two models diverge once $\rho$ approaches 1 — the open system's unbounded queue growth under saturation *is* §2's exponential knee with no self-throttling to soften it. `profile-spike-test.md` §2 already codifies the practical rule to follow; nothing here overrides it.

## 4. Practical k6 Sizing Formulas

$$N_{\text{VUs}} = \text{Target RPS} \times (\text{Mean Latency (s)} + \text{Think Time (s)})$$

**This is Little's Law from §1 applied in practice, not a separate formula** — $N_{\text{VUs}}$ is $L$, Target RPS is $\lambda$, and (Mean Latency + Think Time) is $W$. The two are the same equation; §4 exists only to spell out the practical inputs an agent actually has on hand at PLAN time.

**`Mean Latency` must come from `PERF_SPEC.md`'s existing SLO target for the route in question (its p95 or p50 figure) — never a number invented for this calculation.** Using an unsourced latency estimate here would smuggle an unmeasured assumption into what looks like a rigorous formula.

Worked example (EShop illustrative numbers, per the disclaimer above): a route with a `PERF_SPEC.md` p95 target of 400ms and an assumed 2s think time, needing to sustain 50 RPS:

$$N_{\text{VUs}} = 50 \times (0.4 + 2.0) = 120 \text{ VUs}$$

**This result is a starting point for the ramp target, never a confirmed final figure.** Do not write `120` directly into `PERF_PLAN.md`'s Per-Strategy Workload Boundaries as if it were validated — PLAN must still run the actual k6 script and adjust the VU count based on what's genuinely observed (measured RPS achieved, actual latency under that VU count) before treating any number as final. This formula only tells you where to start ramping, not where the system actually lands.

## 5. Application to Spike & Stress Tests

Under an open-system Spike executor, once $\lambda$ exceeds $c \cdot \mu$ ($\rho > 1$), the theoretical queue grows without the self-throttling a closed system provides — this is the mathematical basis for the backlog-growth signal `profile-spike-test.md`/`rca-spike.md` treat as the open-system saturation tell (Layer 2/3 in `rca-spike.md`'s Diagnostic Matrix). The math here explains *why* that backlog appears; `rca-spike.md`'s recovery-window measurement (`preSpikeLatency`/`postSpikeLatency`) is still what actually confirms it happened.

**Stress does not use §4's formula.** §4 assumes a known Target RPS to solve for $N_{\text{VUs}}$ — but Stress deliberately does not know its target VU count in advance; finding the unknown breaking point is the entire point of the strategy (`rca-load-stress.md`, `profile-stress-test.md`). Applying §4 here would defeat Stress's purpose by pre-committing to a VU count the strategy exists specifically to discover. §4 applies only to Load and Spike, where Target RPS is already known from `PERF_SPEC.md`.
