---
name: bottleneck-root-cause-analysis
description: Use when executing full-load performance tests, conducting 4-layer generalized architecture stack root-cause analysis, running Sub-Agent Audit Gate 2, or writing perf-test/reports/audit-rca-{strategy}.md.
---

# Bottleneck Root Cause Analysis

## Overview

Runs the full load profile for one declared strategy against `perf-test/PERF_SPEC.md`/`perf-test/PERF_PLAN.md`, captures raw telemetry, and diagnoses root cause across the 4-layer generalized architecture stack (Transport → Application → Data → Infrastructure) before submitting the draft to `bottleneck-auditor` for **Audit Gate 2** — the deepest of the three Sub-Agent gates, since its `APPROVED` verdict becomes the evidentiary basis for SHIP's final scorecard.

## When to Use

- The `/perf-audit` command is invoked.
- After `perf-test/reports/verify-sanity-{strategy}.md` for this strategy exists with `AUDIT_VERDICT: APPROVED`.
- In a multi-strategy engagement: once per declared strategy, strictly sequential. The current strategy's AUDIT — including its own Sub-Agent gate — must reach a terminal state (`APPROVED`, or a user-escalated stop after 3 consecutive `REJECTED`) before the next strategy's AUDIT begins. Never interleave raw log capture across strategies.

## Core Process / Workflow

1. **Pre-flight Verification & Baseline Reuse Check.** Read `perf-test/reports/verify-sanity-{strategy}.md` for this strategy and confirm its attached `[SUB-AGENT ADVERSARIAL AUDIT REPORT]` shows `AUDIT_VERDICT: APPROVED`. Confirm the matching row in `perf-test/PERF_PLAN.md`'s Clean Baseline Verification Checklist is still `PASS` for this strategy. **AUDIT does not perform its own separate baseline reset — it reuses the exact reset VERIFY already executed and recorded for this strategy.** This is a deliberate architectural decision, not an oversight: VERIFY's 1 VU / 30s sanity run generates a negligible footprint (on the order of ~14 requests, versus a full-load run's thousands) and does not constitute the "warm, polluted state" Non-Negotiable 2 exists to guard against. Reusing the same `PASS` row means VERIFY and AUDIT measure the *same* clean baseline — which is methodologically correct, not a shortcut — resetting a second time between them would not make the comparison any cleaner, only slower. **If VERIFY is not `APPROVED` for this strategy, or the checklist row is not `PASS`, STOP** — do not proceed to Step 2.
2. **Full Load Execution & Raw Telemetry Capture.** Run `perf-test/scripts/{strategy}.k6.js` with its full configured scenario (not the 1 VU sanity configuration used by VERIFY). Capture the **complete, unedited** raw CLI output and persist it to `perf-test/logs/{strategy}-audit.log` — never trim, summarize, or paraphrase away lines before they are logged. Optional: if `perf-test/observability/docker-compose.yml` exists, ask the user a single light question — "Is the observability stack currently running?" — no STOP, no escalation either way. If confirmed running, add `--out experimental-prometheus-rw --tag testid={strategy}-audit-{timestamp}` to the k6 command (per `references/observability-stack-setup.md` §5); if not confirmed, run the command exactly as before with no changes. This flag never alters what gets captured into `perf-test/logs/{strategy}-audit.log` — the raw log capture requirement is identical either way.
3. **JIT Reference Loading & 4-Layer Root-Cause Analysis.** Apply the JIT Protocol: load all four layer references in full — `rca-layer1-transport.md`, `rca-layer2-application.md`, `rca-layer3-data.md`, `rca-layer4-infrastructure.md` — since every AUDIT must inspect all four layers regardless of where the eventual root cause is isolated (Non-Negotiable 3; `bottleneck-auditor.md`'s 4-layer enforcement). Additionally load **exactly one** Strategy Audit Matrix matching the strategy under test — `rca-load-stress.md`, `rca-spike.md`, or `rca-soak.md` — and leave the non-matching matrix files unread. The quick-reference table below only prioritizes *where to look first*; it never excuses skipping a layer:

   | SUT Characteristic (from `PERF_SPEC.md`'s Target SUT Stack) | Layer Most Likely to Show the Primary Signal |
   |---|---|
   | Single-writer datastore (e.g. SQLite) | Layer 3 — Data (`SQLITE_BUSY` under concurrent writes) |
   | Single-process runtime (e.g. Node.js) | Layer 2 — Application (event-loop lag, unbounded in-memory growth) |
   | Connection-pooled service (e.g. JVM + Postgres) | Layer 2/3 — Application/Data (pool exhaustion) |
   | Load generator under-resourced relative to the SUT | Layer 1 — Transport (false-positive latency from the k6 side, not the SUT) |
   | OS/container resource ceilings (cgroup CPU/RSS caps) | Layer 4 — Infrastructure |

   Draft the Master's findings from the raw log, actively hunting up front for the error signatures `bottleneck-auditor.md` is known to check for — `SQLITE_BUSY`/`SQLITE_LOCKED`, `5xx` responses, `401`/`403` responses a loose `check()` may have silently counted as successful, and connection resets/timeouts — so the draft doesn't hand the Sub-Agent an easy, avoidable rejection. Record evidence (or an explicit `No signal at this layer`) for **all four layers**, even when the eventual root cause is isolated to one.
4. **Sub-Agent Gate 2 Submission & Report Persistence.** Assemble the payload — **exactly 3 clean components**: target SLOs from `perf-test/PERF_SPEC.md`, the raw `perf-test/logs/{strategy}-audit.log`, and the Master's draft — and spawn `bottleneck-auditor` via the Task tool in an isolated context, never leaking the Master's chain-of-thought. On `AUDIT_VERDICT: APPROVED`, persist the audited result to `perf-test/reports/audit-rca-{strategy}.md`, pasting the `[SUB-AGENT ADVERSARIAL AUDIT REPORT]` block **verbatim** — never paraphrased or reconstructed. On `AUDIT_VERDICT: REJECTED`, apply the `REQUIRED_CORRECTIONS` exactly and resubmit a revised draft for a fresh audit pass; **after 3 consecutive `REJECTED` verdicts for this same strategy, stop the retry loop and escalate directly to the user** with all 3 verdicts and their contradictions. This retry counter is scoped **independently per strategy** — a rejection streak against `spike` does not carry over from, or into, `baseline`'s counter (`AGENTS.md` §4, Retry Limit).

## Common Rationalizations

| Common Agent Rationalization | Engineering Reality |
| --- | --- |
| "CPU is clearly pegged at 100%, that's obviously the bottleneck — no need to check the other 3 layers." | High CPU is frequently a symptom, not a cause (e.g. spin-locking from DB contention or event-loop starvation). All 4 layers must be inspected and recorded before attributing root cause to any single one. |
| "The draft looks solid, I'll present it directly instead of spawning the Sub-Agent." | Self-grading is exactly what Gate 2 exists to prevent — no AUDIT draft reaches the user or gets persisted without a fresh `AUDIT_VERDICT: APPROVED` for that exact draft. |
| "VERIFY is basically a formality, let's skip straight to the full load run." | VERIFY's `APPROVED` verdict is AUDIT's required input contract — running a full-load test against a script that was never sanity-checked risks burning an expensive run on a defect a 1 VU pass would have caught in seconds. |
| "I'll write to `audit-rca.md`, it's simpler than tracking the strategy suffix." | A fixed filename silently overwrites the previous strategy's persisted evidence the moment the next strategy's AUDIT runs — every report requires its explicit `{strategy}` suffix, no exceptions. |
| "VERIFY already reset the baseline, but let's reset again before AUDIT just to be safe." | Unnecessary: VERIFY's 1 VU/30s footprint (~14 requests) does not constitute a polluted state, and AUDIT is designed to reuse that same `PASS` row rather than re-reset. A second reset adds time without adding rigor — the architecture decision here is deliberate, not a corner being cut. |
| "The Sub-Agent's block is a bit verbose, I'll summarize the key points instead of pasting it whole." | The `[SUB-AGENT ADVERSARIAL AUDIT REPORT]` block must be pasted **verbatim** into the persisted report — paraphrasing it reintroduces exactly the kind of Master-framing bias the independent audit exists to eliminate. |
| "I'll just run `docker compose up -d` myself to save the user a step." | Running the observability stack is exclusively the user's manual action — the agent's role stops at generating a correct, runnable file. Starting a background Docker daemon process without explicit, in-the-moment user execution crosses outside what this suite's agents are scoped to do. |

## Red Flags

- AUDIT runs for a strategy whose `verify-sanity-{strategy}.md` is not `AUDIT_VERDICT: APPROVED`, or whose `PERF_PLAN.md` baseline row is not `PASS`.
- An RCA conclusion is reached with evidence recorded for fewer than all 4 layers, even when the root cause is isolated to one.
- The Master's chain-of-thought or reasoning narrative leaks into the Sub-Agent payload.
- A draft is shown to the user, or persisted to `perf-test/reports/`, with no fresh `AUDIT_VERDICT: APPROVED` attached.
- `perf-test/reports/audit-rca-{strategy}.md`'s Metadata header is missing its `Baseline Reset Reference` line.
- The `[SUB-AGENT ADVERSARIAL AUDIT REPORT]` block is paraphrased, summarized, or reconstructed instead of pasted verbatim.
- `perf-test/logs/{phase}-audit.log` or `perf-test/reports/audit-rca-{phase}.md` uses a fixed/generic filename instead of the `{strategy}`-suffixed convention.
- The retry loop continues past 3 consecutive `REJECTED` verdicts for the same strategy without stopping and escalating to the user.
- The agent executes any `docker`/`docker compose` command itself instead of only generating the configuration files and instructing the user to run them.

## Required Output Format

Persist `perf-test/reports/audit-rca-{strategy}.md` in this shape — metadata header, per-endpoint telemetry vs. SLO, 4-layer RCA matrix, error signature distribution, then the attached audit block.

**Note:** Route paths and figures in this template (`/api/search`, `/api/cart`, `/api/checkout`, all `{{...}}` values) illustrate the EShop reference scenario only — substitute the actual `In-Scope Routes` from the target project's `PERF_SPEC.md`; only the section structure and sourcing rules are mandatory to preserve.

````markdown
# audit-rca-{strategy}.md

## Metadata
- Strategy: baseline
- Phase: AUDIT (Sub-Agent Audit Gate 2)
- Script: perf-test/scripts/baseline.k6.js
- Baseline Reset Reference: PERF_PLAN.md Clean Baseline Verification Checklist row "Load (baseline)" — PASS (reused from VERIFY; see Core Process Step 1)
- Machine Reference: PERF_PLAN.md Environment Parity Summary — {{CPU_MODEL}}, {{TOTAL_RAM_GB}}GB RAM

## Full Load Telemetry Table (Per-Endpoint vs. SLO)

```text
GET /api/search:     RPS {{MEASURED_RPS}} vs {{PERF_SPEC_TARGET_RPS}} target -> {{PASS_OR_FAIL}}
                      p95 {{MEASURED_P95_MS}}ms vs {{PERF_SPEC_P95_MS}}ms target -> {{PASS_OR_FAIL}}
POST /api/cart:       p95 {{MEASURED_P95_MS}}ms vs {{PERF_SPEC_P95_MS}}ms target -> {{PASS_OR_FAIL}}
POST /api/checkout:   Error Rate {{MEASURED_ERROR_RATE}}% vs {{PERF_SPEC_MAX_FAIL_RATE}}% max -> {{PASS_OR_FAIL}}
```

Never collapse this into a single averaged figure — one endpoint's breach fails that endpoint's row regardless of how other endpoints performed.

## 4-Layer RCA Inspection Matrix

| Layer | Evidence | Verdict |
|---|---|---|
| Layer 1 — Transport | {{EVIDENCE_OR_NO_SIGNAL}} | {{ROOT_CAUSE_OR_CLEAR}} |
| Layer 2 — Application | {{EVIDENCE_OR_NO_SIGNAL}} | {{ROOT_CAUSE_OR_CLEAR}} |
| Layer 3 — Data | {{EVIDENCE_OR_NO_SIGNAL}} | {{ROOT_CAUSE_OR_CLEAR}} |
| Layer 4 — Infrastructure | {{EVIDENCE_OR_NO_SIGNAL}} | {{ROOT_CAUSE_OR_CLEAR}} |

## Error Signature Distribution

| Signature | Count | Layer Attribution |
|---|---|---|
| SQLITE_BUSY / SQLITE_LOCKED | {{COUNT}} | Layer 3 — Data |
| HTTP 5xx | {{COUNT}} | Layer 2/3 |
| Connection reset / timeout | {{COUNT}} | Layer 1 — Transport |
| HTTP 401/403 (unauthenticated as designed) | {{COUNT}} | N/A — not a bottleneck signal |

## [SUB-AGENT ADVERSARIAL AUDIT REPORT]

```text
================================================================================
                     SUB-AGENT ADVERSARIAL AUDIT REPORT
================================================================================
AUDIT_VERDICT      : APPROVED
RAW_LOG_CHECK      : Independently counted {{TOTAL_REQUESTS}} total requests, {{TOTAL_ERRORS}} errors found
SLO_COMPLIANCE     : GET /api/search: p95 {{MEASURED_P95_MS}}ms vs {{PERF_SPEC_P95_MS}}ms target -> PASS
BYPASSED_ERRORS    : None found
REQUIRED_CORRECTIONS: None — cleared for release.
================================================================================
```
````

- The `[SUB-AGENT ADVERSARIAL AUDIT REPORT]` block is mandatory and must be pasted verbatim from `bottleneck-auditor`'s actual output — never paraphrased or reconstructed by the Master.
- The `Machine Reference` line MUST cite `PERF_PLAN.md`'s Environment Parity Summary Host Machine Specification for this session — never left blank and never typed independently of what `PERF_PLAN.md` already records.
- Every layer row in the 4-Layer RCA Inspection Matrix must be filled in, even when the verdict is "No signal at this layer" — an omitted row is non-compliant.
- Prose outside the tables/blocks is capped at 3-5 bullet points.
