---
name: perf-requirements-and-slo
description: Use when defining target SLOs, parsing docs/ artifacts (.har, spec.md, openapi.json), establishing endpoint workload models, or writing perf-test/PERF_SPEC.md.
---

# Performance Requirements and SLO Definition

## Overview

Parses the target project's `docs/` input artifacts and negotiates the target SLOs, SUT profile, and test strategy/strategies *before* any k6 script is written or any test is executed, persisting the result to `perf-test/PERF_SPEC.md` — the hard input contract every later phase reads from. Owned and executed directly by the Master Agent (`perf-architect`); no Sub-Agent audit gate applies to DEFINE.

## When to Use

- The `/perf-spec` command is invoked.
- At the start of a new performance engagement, before `/perf-plan` or `/perf-script` are invoked.
- A user asks to "load test the app" or "check performance" without having stated concrete numeric targets, SUT stack, or a strategy yet.
- `perf-test/PERF_SPEC.md` does not exist yet, or an existing one is missing SLOs, metadata, or a declared strategy for work about to begin.
- Business/product requirements change (e.g. a new expected launch traffic figure) and existing SLOs need to be revised.

## Core Process / Workflow

1. **Input Inspection from `docs/`.** Read the target project's `docs/` directory (or its root if `docs/` doesn't exist) for `.har` captures, `spec.md`, and/or `openapi.json`. Identify which artifact(s) are present — this becomes the `Ingestion Source` metadata that BUILD's JIT protocol later uses to pick `parse-har.md`, `parse-openapi.md`, or the `parse-codebase.md` fallback. **If `docs/` is missing or empty, STOP and ask the user for the input artifacts — never invent, assume, or recall a spec from an unrelated prior session** (Workspace Boundary Rule, `AGENTS.md` §1).
2. **Endpoint & SLO Extraction.** From the ingested artifact, extract endpoints, HTTP methods, parameters, and business flow. Prioritize revenue-critical and highest-traffic paths first and state the in-scope route list explicitly — do not silently attempt every route in the system. For each in-scope route, establish:
   - Target RPS (sustained throughput expected in production).
   - Max Error Rate %: if the stakeholder states an explicit ceiling, use it with `Source: Stakeholder-confirmed`. If not, consult `references/slo-cheatsheet.md` for the industry-standard default for this route type/traffic class, and label the row `ASSUMED — unconfirmed (default via slo-cheatsheet.md)` — never silently hard-code 1.0% as if it required no sourcing.
   - Latency percentiles: p50, p95, p99 (in ms) — an average alone is never sufficient.
   - If the user/stakeholder cannot supply a number, do not invent one silently: label it `ASSUMED — unconfirmed` and flag it for reconciliation before `/perf-plan`.
   - Also identify the **Target SUT Stack** (e.g. Node.js/SQLite, JVM/Postgres) from `docs/` or a light codebase check — this becomes required metadata for the 4-layer RCA performed later in AUDIT.
3. **Strategy Selection (Load / Stress / Spike / Soak).** Choose the test strategy or strategies that match the engagement's actual goal — steady-state capacity (**Load**), breaking point (**Stress**), sudden traffic burst (**Spike**), or long-duration leak/drift detection (**Soak**). **Multi-Strategy declarations are supported and expected when the user's goal spans more than one** (e.g. a Load baseline *and* a Spike test in the same engagement) — list every declared strategy explicitly; each one later gets its own BUILD script and its own sequential VERIFY/AUDIT loop pass (`AGENTS.md` §2, Multi-Strategy Lifecycle Loop). For every declared strategy, state its workload boundaries (VUs, ramp shape, duration) up front — this is required even at DEFINE stage so PLAN/BUILD have concrete boundaries to operationalize (Non-Negotiable 4, Surface Assumptions).
4. **Spec Persistence to `perf-test/PERF_SPEC.md`.** If `perf-test/` does not exist yet, create it along with `scripts/`, `logs/`, `reports/` as this engagement's first artifact-producing step. Write (or update) `perf-test/PERF_SPEC.md` with the Engagement Metadata header, the Target SLO & Metric Baseline Matrix, the Mixed Workload Profile, and the per-strategy workload boundaries. This file is the single source of truth every downstream phase and the `bottleneck-auditor` Sub-Agent reads from — an SLO or strategy that only exists in chat history does not count, and no later phase may proceed without it.

## Common Rationalizations

| Common Agent Rationalization | Engineering Reality |
| --- | --- |
| "This is a small project, no need to write `perf-test/PERF_SPEC.md`, I'll just start scripting." | Without a persisted spec, VERIFY/AUDIT have nothing to grade compliance against — a small engagement still needs a contract, or every later phase's "PASS" is meaningless. |
| "`docs/` is empty, but I remember this app's routes from a previous session, I'll draft the spec from memory." | The Workspace Boundary Rule requires input sourced from `docs/` in *this* engagement — recall from an unrelated prior session is exactly the kind of unverified assumption this rule exists to block. Stop and ask for the artifacts. |
| "`spec.md` doesn't state numeric SLOs, I'll estimate reasonable industry-standard values." | Non-Negotiable 1 (Never Assume Latency) forbids presenting an invented number as fact. Label it `ASSUMED — unconfirmed` and route it back to the stakeholder instead. |
| "Average response time captures it well enough, I'll skip p95/p99." | Averages hide tail latency — a service can have a fast average and a terrible p99 that a meaningful fraction of real users experience. p50/p95/p99 are mandatory. |
| "This is straightforward CRUD, no need to note the SUT's architecture limits yet." | Non-Negotiable 4 (Surface Assumptions) requires stating SUT architecture limits (e.g. single-writer SQLite, single-process Node.js) up front — deferring this to AUDIT leaves the later RCA without the baseline context to interpret a bottleneck correctly. |
| "The user only mentioned load testing, I won't bother listing it as a declared strategy — I'll just imply it." | An implied strategy is not a declared one. Every strategy the engagement will actually run — even just one — must be named explicitly in `perf-test/PERF_SPEC.md`'s metadata, because BUILD/VERIFY/AUDIT key off that declared list. |

## Red Flags

- DEFINE proceeds despite `docs/` being missing or empty — a spec gets fabricated from assumption instead of stopping to ask the user.
- `perf-test/PERF_SPEC.md` is written with average-only latency, no p95/p99 defined for a route under test.
- An SLO figure appears with no `Source` label (`Stakeholder-confirmed` vs. `ASSUMED — unconfirmed`).
- A Max Error Rate % or other SLO ceiling is applied as a silent default with no trace to either the stakeholder or `references/slo-cheatsheet.md`.
- The spec file is written outside `perf-test/` — to the project root, or worse, inside `.claude/` — a direct Workspace Boundary Rule violation.
- Multiple strategies are discussed in conversation but only one is persisted in `perf-test/PERF_SPEC.md`, or the Declared Test Strategy metadata field is omitted entirely.
- The Engagement Metadata header (Target SUT Stack / Ingestion Source / Declared Test Strategy) is missing — this silently breaks the JIT reference-loading protocol every downstream command relies on.
- A workload ratio defaults to an even split across endpoints with no stated justification.
- A declared strategy has no stated VU/ramp/duration boundary, leaving PLAN/BUILD nothing concrete to build against.

## Required Output Format

Persist `perf-test/PERF_SPEC.md` in this shape — metadata header first, then the SLO matrix, workload ratio, and per-strategy boundaries:

```markdown
# PERF_SPEC.md

## Engagement Metadata
- Target SUT Stack: Node.js (Express) + SQLite, single-process/single-writer
- Ingestion Source: docs/checkout-flow.har
- Declared Test Strategy: Load (baseline), Spike
- In-Scope Routes: GET /api/search, POST /api/cart, POST /api/checkout

## Target SLO & Metric Baseline Matrix

| Route/Endpoint      | Target RPS | Max Fail Rate % | p50 (ms) | p95 (ms) | p99 (ms) | Source                 |
|----------------------|-----------:|-----------------:|---------:|---------:|---------:|--------------------------|
| GET /api/search       |         50 |              1.0 |      120 |      400 |      700 | Stakeholder-confirmed    |
| POST /api/cart        |         20 |              1.0 |      150 |      450 |      800 | Stakeholder-confirmed    |
| POST /api/checkout    |          8 |              0.5 |      300 |      900 |     1500 | ASSUMED — unconfirmed    |

## Mixed Workload Profile
- Search: 60%
- Cart: 30%
- Checkout: 10%

## Per-Strategy Workload Boundaries

| Strategy         | VUs / Ramp Shape                        | Duration | Goal                          |
|-------------------|------------------------------------------|----------|--------------------------------|
| Load (baseline)   | 50 VU flat                               | 10m      | Steady-state capacity          |
| Spike             | 50→500 VU ramp in 30s, hold 2m, ramp down| 5m       | Burst resilience               |
```

- Every SLO row must show a `Source` of either `Stakeholder-confirmed` or `ASSUMED — unconfirmed`; a bare number with no source is non-compliant.
- Every declared strategy in the metadata header must have a matching row in the Per-Strategy Workload Boundaries table — a strategy named but not bounded is non-compliant.
- Prose outside the tables is capped at 3-5 bullet points (e.g. scope notes, open questions for the stakeholder).
