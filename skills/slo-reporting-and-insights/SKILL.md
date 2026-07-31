---
name: slo-reporting-and-insights
description: Use when synthesizing multi-strategy executive scorecards, validating overall SLO compliance, running Sub-Agent Audit Gate 3 (Final Sign-off), or writing perf-test/reports/final-gate-scorecard.md.
---

# SLO Reporting and Insights

## Overview

Aggregates every strategy declared in `perf-test/PERF_SPEC.md` from their already-`APPROVED` `perf-test/reports/audit-rca-*.md` files into one executive scorecard, validates overall SLO compliance without smoothing over any single strategy's breach, and submits the draft to `bottleneck-auditor` for **Audit Gate 3 — Final Sign-off** before persisting `perf-test/reports/final-gate-scorecard.md` with an explicit `FINAL GATE DECISION: PASS` or `FINAL GATE DECISION: REJECT` verdict.

## When to Use

- The `/perf-gate` command is invoked.
- Only once **every** strategy declared in `perf-test/PERF_SPEC.md`'s `Declared Test Strategy` metadata has a corresponding `perf-test/reports/audit-rca-{strategy}.md` with `AUDIT_VERDICT: APPROVED` — SHIP is the terminal phase and has no partial-completion mode.

## Core Process / Workflow

1. **Multi-Strategy Completeness & Gate Pre-flight Check.** Read `perf-test/PERF_SPEC.md`'s `Declared Test Strategy` list. Confirm **every** declared strategy has a `perf-test/reports/audit-rca-{strategy}.md` on disk with `AUDIT_VERDICT: APPROVED` in its attached `[SUB-AGENT ADVERSARIAL AUDIT REPORT]` block. **If any strategy is missing, still pending, or its last AUDIT pass was `REJECTED`, STOP** — name exactly which strategy is blocking and instruct the user to run `/perf-audit` for it. Never sign off on a partial set, even if the completed strategies all look clean.
2. **Aggregate Telemetry & Executive Scorecard Synthesis.** Synthesize p95/p99/RPS/Error Rate % and the 4-layer RCA conclusion from **every** `audit-rca-*.md` file gathered in Step 1 — read the already-audited reports, never the underlying raw `.log` files (that RCA work is already `APPROVED` evidence from Gate 2; re-deriving it here would be redundant and out of Gate 3's scope). Cross-reference each figure against `perf-test/PERF_SPEC.md`'s Target SLO Matrix. **Each strategy keeps its own independent PASS/FAIL verdict per endpoint — never average or round across strategies to smooth over a single FAIL.** A `Load` strategy passing cleanly does not offset a `Spike` strategy's SLO breach; both appear in the scorecard exactly as their source reports state.
3. **Master Scorecard Draft Generation.** Draft `final-gate-scorecard.md`: Engagement Metadata (declared strategies and their source `audit-rca-*.md` files), the Executive Scorecard Table (per strategy, per endpoint — see Required Output Format), a 7 Non-Negotiables Compliance Checklist, Key Bottlenecks & Risks (synthesized from each strategy's 4-Layer RCA findings), a proposed `PASS`/`REJECT` verdict, and brief CI/CD Integration Guidance (e.g. parsing the `FINAL GATE DECISION` line, or the k6/CI exit code, to auto-block a deploy pipeline on `REJECT`).
4. **Sub-Agent Gate 3 Submission & Scorecard Persistence.** Assemble the payload — **exactly 3 clean components**: target SLOs from `perf-test/PERF_SPEC.md`, **every already-`APPROVED` `perf-test/reports/audit-rca-*.md` file** for all declared strategies (never the underlying raw logs — Gate 3 audits aggregation completeness and consistency, not raw-log RCA, which was already performed and approved at Gate 2), and the Master's scorecard draft. Spawn `bottleneck-auditor` via the Task tool in an isolated context, never leaking the Master's chain-of-thought. On `AUDIT_VERDICT: APPROVED`, persist `perf-test/reports/final-gate-scorecard.md`, pasting the `[SUB-AGENT ADVERSARIAL AUDIT REPORT]` block **verbatim**. On `AUDIT_VERDICT: REJECTED`, apply the `REQUIRED_CORRECTIONS` exactly and resubmit a revised draft for a fresh audit pass; **after 3 consecutive `REJECTED` verdicts, stop the retry loop and escalate directly to the user** with all 3 verdicts and their contradictions. **Unlike VERIFY/AUDIT, this retry counter is scoped to the SHIP phase as a whole for the current engagement, not per strategy** — SHIP audits every strategy's aggregation at once, so there is no per-strategy split at this phase (`AGENTS.md` §4, Retry Limit).

## Common Rationalizations

| Common Agent Rationalization | Engineering Reality |
| --- | --- |
| "2 of 3 declared strategies are `APPROVED`, close enough — let's ship the scorecard for those and note the third as pending." | SHIP has no partial-completion mode. A scorecard that omits a declared strategy isn't incomplete, it's misleading — it implies a clean bill of health the engagement never actually earned. STOP and name the blocking strategy instead. |
| "Gate 3 is basically just a formatting pass over already-approved reports, I'll skip the Sub-Agent this time." | Gate 3 exists specifically to catch aggregation errors — a strategy quietly dropped, a `FAIL` smoothed into an average, a contradiction between two reports — that a formatting pass alone would never catch. Every draft still requires a fresh `AUDIT_VERDICT: APPROVED`. |
| "The Sub-Agent said `REJECTED`, but the user really wants a `PASS` — I'll present `PASS` anyway and note the objection." | The Master cannot overrule a `REJECTED` verdict for any reason, including user preference. Apply the `REQUIRED_CORRECTIONS` and resubmit; only an `APPROVED` verdict permits presenting `FINAL GATE DECISION: PASS`. |
| "I'll write to `gate-scorecard.md` instead of `final-gate-scorecard.md`, it's close enough." | The filename is a fixed contract other tooling (CI/CD parsing, downstream engagements) may depend on — use the exact name `perf-test/reports/final-gate-scorecard.md`, not an approximation. |
| "The AUDIT reports look thin on RCA detail, I'll re-run the raw logs myself to fill in the gaps for this scorecard." | Re-deriving RCA from raw logs at Gate 3 is out of scope — that analysis was already performed and independently `APPROVED` at Gate 2. If a Gate 2 report is genuinely insufficient, that strategy needs to re-enter AUDIT, not have its RCA silently redone inside SHIP. |
| "The Sub-Agent's block is long, I'll summarize the highlights instead of pasting the whole thing." | The `[SUB-AGENT ADVERSARIAL AUDIT REPORT]` block must be pasted **verbatim** into the persisted scorecard — summarizing it reintroduces the Master-framing bias the independent Gate 3 audit exists to eliminate. |

## Red Flags

- SHIP runs while any strategy declared in `PERF_SPEC.md` has no `audit-rca-{strategy}.md`, or that strategy's last AUDIT pass was not `APPROVED`.
- A scorecard is shown to the user, or persisted, with no fresh `AUDIT_VERDICT: APPROVED` attached.
- The terminal verdict line is missing, ambiguous, or uses different terminology than exactly `FINAL GATE DECISION: PASS` or `FINAL GATE DECISION: REJECT` (e.g. "SHIP/NO-SHIP," "APPROVED/DENIED").
- The Master's chain-of-thought or reasoning narrative leaks into the Sub-Agent payload.
- The Sub-Agent payload's evidence component contains a raw `.log` file instead of `audit-rca-*.md` reports.
- One strategy's SLO breach is averaged away against another strategy's clean pass in the Executive Scorecard Table.
- The `[SUB-AGENT ADVERSARIAL AUDIT REPORT]` block is paraphrased or reconstructed instead of pasted verbatim.
- The retry loop continues past 3 consecutive `REJECTED` verdicts for the SHIP phase without stopping and escalating to the user.

## Required Output Format

Persist `perf-test/reports/final-gate-scorecard.md` in this shape — metadata header, per-strategy/per-endpoint scorecard, bottlenecks summary, CI/CD guidance, the terminal verdict line, the compliance checklist, then the attached audit block.

**Note:** Route paths and figures in this template (`/api/search`, `/api/cart`, `/api/checkout`, all `{{...}}` values) illustrate the EShop reference scenario only — substitute the actual `In-Scope Routes` from the target project's `PERF_SPEC.md`; only the section structure and sourcing rules are mandatory to preserve.

````markdown
# final-gate-scorecard.md

## Engagement Metadata
- Declared Strategies: Load (baseline), Spike
- Source Reports: perf-test/reports/audit-rca-baseline.md (APPROVED), perf-test/reports/audit-rca-spike.md (APPROVED)

## Executive Scorecard Table

| Strategy | Endpoint | Target SLO | Measured Result | Status |
|---|---|---|---|:---:|
| Load (baseline) | GET /api/search | p95 < {{PERF_SPEC_P95_MS}}ms | p95 {{MEASURED_P95_MS}}ms | {{PASS_OR_FAIL}} |
| Load (baseline) | POST /api/checkout | Error Rate < {{PERF_SPEC_MAX_FAIL_RATE}}% | {{MEASURED_ERROR_RATE}}% | {{PASS_OR_FAIL}} |
| Spike | GET /api/search | Recovery within 10% of pre-spike p95 | {{MEASURED_RECOVERY_PERCENT}}% | {{PASS_OR_FAIL}} |

Never collapse rows across strategies or endpoints into an average — one `FAIL` fails that row regardless of how the rest of the table reads.

## Key Bottlenecks & Risks

- {{SUMMARY_FROM_STRATEGY_AUDIT_RCA_4_LAYER_FINDINGS}}

## CI/CD Integration Guidance

- Parse the `FINAL GATE DECISION:` line from this file in a CI pipeline step; treat anything other than an exact `PASS` as a failing step.
- Alternatively, gate on the k6/CI process exit code from the underlying AUDIT runs if your pipeline already captures it.
- Re-run `/perf-gate` only after every blocking strategy has a fresh `APPROVED` `audit-rca-{strategy}.md` — do not re-trigger CI against a stale scorecard.

## FINAL GATE DECISION: PASS

## 7 Non-Negotiables Compliance Checklist

| # | Non-Negotiable | Status |
|---|---|:---:|
| 1 | Never Assume Latency | OK |
| 2 | Enforce Clean Baseline | OK |
| 3 | Measure Before Optimizing | OK |
| 4 | Surface Assumptions | OK |
| 5 | Reject Flawed Logic | OK |
| 6 | Require Runtime Evidence | OK |
| 7 | Independent Sub-Agent Audit | OK |

## [SUB-AGENT ADVERSARIAL AUDIT REPORT]

```text
================================================================================
                     SUB-AGENT ADVERSARIAL AUDIT REPORT
================================================================================
AUDIT_VERDICT      : APPROVED
RAW_LOG_CHECK      : {{N}} of {{N}} declared strategies present as APPROVED audit-rca-*.md reports
SLO_COMPLIANCE     : Load (baseline): all endpoints PASS. Spike: recovery check PASS.
BYPASSED_ERRORS    : None found
REQUIRED_CORRECTIONS: None — cleared for release.
================================================================================
```
````

- The terminal verdict line must read exactly `FINAL GATE DECISION: PASS` or `FINAL GATE DECISION: REJECT` — no other terminology, no hedged phrasing.
- The `[SUB-AGENT ADVERSARIAL AUDIT REPORT]` block is mandatory and must be pasted verbatim from `bottleneck-auditor`'s actual output.
- Every declared strategy must appear in the Executive Scorecard Table — a strategy present in `PERF_SPEC.md` but absent from this table is non-compliant.
- Prose outside the tables/blocks is capped at 3-5 bullet points.
