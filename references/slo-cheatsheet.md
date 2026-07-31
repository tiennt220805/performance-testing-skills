# Standard SLO Benchmarks and Metric Cheatsheet

**Note:** System tier examples and thresholds in this file represent general industry benchmarks only — whenever stakeholder-defined SLOs are available in `PERF_SPEC.md`, those explicit figures override these defaults; only the metric definitions, tier classifications, and provenance attribution rules are mandatory to preserve.

Unlike other reference files in this suite, numbers in this file's lookup matrices are **not** `{{...}}` placeholders to be replaced per project — they *are* the industry-default source of truth this file exists to provide.

## 1. Metric Vocabulary & Definitions

| Term | Definition |
|---|---|
| **RPS** | Requests per second — sustained throughput. This suite provides no industry default for it (see §2's boundary note); it is always business-specific. |
| **p50** | Median request latency — half of all requests finish faster than this, half slower. Useful as a "typical" figure, but hides everything about the slow tail. |
| **p90** | 90th-percentile latency — 1 in 10 requests is slower than this. A leading indicator that tail latency is starting to widen before it reaches p99. |
| **p95** | 95th-percentile latency — 1 in 20 requests is slower than this. The most common SLO gate in this suite's `PERF_SPEC.md` matrix. |
| **p99** | 99th-percentile latency — 1 in 100 requests is slower than this. Captures the tail that directly correlates with the worst individual user experiences. |
| **Error Rate %** | Percentage of requests that failed (non-2xx/3xx, timeout, connection error) out of total requests issued during the measurement window. |
| **TTFB** | Time to First Byte — the interval between sending a request and receiving the first byte of the response. Approximates server-side processing time before response-body transfer begins; in k6 terms, closely tracked by `http_req_waiting`. |

**Why percentiles, never averages:** an average blends every request into a single number, and a small cluster of very slow requests can be entirely invisible behind a large cluster of fast ones — the mean can look healthy while a meaningful fraction of real users experience multi-second waits. Percentiles report exactly what fraction of users saw what experience, which an average structurally cannot express. This is why `PERF_SPEC.md`'s SLO matrix requires p50/p95/p99 columns and has no "average" column at all.

## 2. Standard Tier-Based SLO Lookup Matrix

Per-endpoint defaults, feeding `PERF_SPEC.md`'s Target SLO & Metric Baseline Matrix (`Route/Endpoint | Target RPS | Max Fail Rate % | p50 | p95 | p99 | Source` — six columns, locked; nothing in this file adds a seventh):

| System Tier / Use-case | Target p95 Latency | Target p99 Latency | Max Error Rate % | Typical Throughput Profile |
|---|---|---|---|---|
| **Interactive UI / Web Navigation** | < 500ms | < 1000ms | < 0.5% | Moderate RPS |
| **Public REST API (Read-Heavy)** | < 200ms | < 500ms | < 0.1% | High RPS |
| **Financial / Checkout / Payment** | < 800ms | < 1500ms | < 0.01% | Burst / High Consistency |
| **Background Async Processing** | < 2000ms | < 5000ms | < 1.0% | Heavy Batch |

**Tier Classification Heuristic.** To pick the right tier for a real route in `PERF_SPEC.md`'s `In-Scope Routes`:

- A route that commits payment, places an order, or otherwise finalizes a financial transaction — regardless of HTTP method — is **Financial / Checkout / Payment**, even if it superficially looks like a normal write endpoint.
- A `GET`-only route serving publicly readable data with no strict consistency guarantee (search results, product listings, public profiles) is **Public REST API (Read-Heavy)**.
- A route whose response is consumed directly by an interactive UI the user is actively waiting on (page loads, form submissions rendering immediately) is **Interactive UI / Web Navigation**.
- A route that returns immediately but whose real work is deferred to a background job/queue (report generation, email dispatch, batch export) is **Background Async Processing** — grade the route's own response time against this tier, not the eventual completion time of the deferred work.
- **If a route doesn't clearly match any tier, ask the stakeholder rather than guessing.** Forcing an ambiguous route into the nearest-sounding tier is exactly the kind of unconfirmed assumption `perf-requirements-and-slo/SKILL.md` exists to prevent.

**No Default for Target RPS — Explicit Boundary.** This cheatsheet provides **no** industry-standard default for Target RPS. Unlike latency percentiles and error-rate ceilings, throughput is inherently business-specific — production traffic volume varies by orders of magnitude between businesses in the same tier. Target RPS must always come from the stakeholder or historical production data, never defaulted from the "Typical Throughput Profile" column above, which is descriptive context only, not a number to copy.

## 3. Provenance & Citation Rules

Applies only to §2's per-endpoint figures being written into `PERF_SPEC.md`'s SLO matrix.

When a route's Max Fail Rate %/p95/p99 is not stakeholder-confirmed and this file's §2 default is used instead, the `Source` column must read exactly:

```text
ASSUMED — unconfirmed (default via slo-cheatsheet.md: <Tier Name>)
```

— with `<Tier Name>` copied verbatim from §2's table (e.g. `Financial / Checkout / Payment`), never paraphrased or shortened.

**Only two forms of `Source` are valid** — `Stakeholder-confirmed`, or `ASSUMED — unconfirmed` with the optional `(default via slo-cheatsheet.md: <Tier Name>)` qualifier when this file supplied the number. Never invent a third form (no "Estimated," "Best guess," "TBD," or similar).

The `ASSUMED` label is a transparency commitment, not an evasion: it tells every downstream reader — PLAN, BUILD, VERIFY, AUDIT, SHIP, and the `bottleneck-auditor` Sub-Agent — exactly which numbers in the engagement were never actually confirmed by a stakeholder (Non-Negotiable 1, Never Assume Latency) and keeps that assumption visible in the artifact itself rather than buried in chat history (Non-Negotiable 4, Surface Assumptions).

## 4. Anti-Patterns in SLO Definition

| Anti-Pattern | Non-Negotiable Violated |
|---|---|
| Applying the same p95 ceiling to every endpoint regardless of what it actually does (a cheap cache-hit `GET` held to the same bar as an expensive multi-table `POST`) | Rule 4 (Surface Assumptions) — a uniform ceiling hides the real per-route cost structure instead of surfacing it. |
| Using average latency instead of a percentile as the SLO gate | Rule 1 (Never Assume Latency) — an average can look healthy while the tail (see §1) is silently failing a meaningful fraction of users. |
| Leaving Max Error Rate % blank, treated as "presumably fine by default" | Rule 6 (Require Runtime Evidence) — AUDIT has nothing to compare a measured error rate against, so no PASS/FAIL verdict can ever be rendered for that endpoint. |
| Copying a tier's benchmark numbers onto a route that doesn't actually match that tier's risk profile (e.g. applying the Financial tier's 0.01% error ceiling to a read-only route with no financial consequence) | Rule 5 (Reject Flawed Logic) — the number looks precise but was never validated against the route's actual context, which is a disguised assumption, not a measurement. |
| Writing CPU/RAM/RSS/concurrent-user figures into `PERF_SPEC.md`'s SLO matrix as if they were business SLOs on par with p95/latency | Confuses §2 (stakeholder-facing SLO) with §5 (internal engineering heuristic) — see §5's explicit boundary below; these are architecturally distinct and must never share a row. |

## 5. Infrastructure & Resource Health Benchmarks

Everything in this section is an **internal engineering health benchmark, not a stakeholder-facing SLO**. It never populates a row in `PERF_SPEC.md`'s Target SLO & Metric Baseline Matrix (which is strictly per-endpoint: RPS/Fail Rate/p50/p95/p99/Source). These figures instead serve two existing consumers: (1) `test-environment-and-baseline/SKILL.md`'s Idle Telemetry Table, when a target project hasn't specified its own idle-CPU/RSS ceiling; (2) `rca-layer4-infrastructure.md`'s AUDIT-time diagnostic thresholds, when judging whether observed CPU/RAM/disk pressure during a full-load run is within a defensible envelope. Citing this section follows the same `ASSUMED — unconfirmed (default via slo-cheatsheet.md: <Row Name>)` convention as §3, but the citation appears inside `PERF_PLAN.md` or the AUDIT report's Evidence line — **never** inside `PERF_SPEC.md`'s SLO matrix.

| System Tier | Idle-State CPU Ceiling | Under-Load CPU Ceiling (sustained) | RSS/Memory Growth Tolerance | Notes |
|---|---|---|---|---|
| **General-purpose service (default)** | < 5% (matches `test-environment-and-baseline/SKILL.md`'s existing idle check — cite it, do not redefine) | < 80% sustained before flagging saturation | Flat within ±10% over a Soak run's early/late window (see `profile-soak-test.md` §5's >20% degradation heuristic — this is a *tighter*, resource-specific companion figure, not a replacement) | General web/API backends |
| **Batch/Async worker** | < 5% | < 95% sustained (batch workloads are expected to run CPU-hot) | Same ±10% tolerance | Background processing tier |
| **Financial/Payment processing** | < 5% | < 70% sustained (lower headroom margin, given consistency requirements from §2's Financial tier) | Same ±10% tolerance | Mirrors §2's Financial tier's tighter latency consistency |

Every value in this table is written as a real number, not a `{{...}}` placeholder — same rationale as §2: this file *is* the default source of truth, not a per-project template to fill in. Do not invent a second, conflicting idle-CPU threshold anywhere else in the suite — the `< 5%` figure above is the same figure `test-environment-and-baseline/SKILL.md` already enforces, cited here, not redefined.

**Concurrent Users / VU sizing — no standalone benchmark here.** This file does **not** provide a standalone "target concurrent users" benchmark — a raw VU count means nothing without the RPS and per-user think-time it's meant to sustain. For estimating the VU count needed to sustain a given target RPS (or vice versa), see `references/queueing-theory-mmc.md`'s Little's Law derivation instead. `PERF_PLAN.md`'s Per-Strategy Workload Boundaries table is where an actual VU count is recorded for a given engagement — never this cheatsheet.
