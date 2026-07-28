---
name: using-performance-testing-skills
description: Core operating protocol and workflow router for the performance-testing-skills suite. Use when starting any k6 performance engineering engagement to determine which skill/command to invoke next in the /perf-spec -> /perf-plan -> /perf-script -> /perf-verify -> /perf-audit -> /perf-gate pipeline, and to enforce the Master-SubAgent adversarial audit loop.
---

# Using Performance Testing Skills

## Overview

Meta-skill and operating protocol for the entire suite: it routes each user intent to the correct `/perf-*` command and skill, and enforces that `/perf-verify`, `/perf-audit`, and `/perf-gate` each pass through an independent `bottleneck-auditor` Sub-Agent audit before any result reaches the user.

## When to Use

- At the start of any session involving performance testing, before invoking any `/perf-*` command.
- Whenever the next step in the lifecycle is ambiguous, or a user request does not map clearly to a single skill.
- Whenever a request would skip a lifecycle phase, skip a clean baseline reset, or bypass the Sub-Agent audit on VERIFY/AUDIT/SHIP.

## Core Process / Workflow

1. Read this skill first, then determine the current lifecycle phase from `AGENTS.md` §2 (`DEFINE -> PLAN -> BUILD -> VERIFY -> AUDIT -> SHIP`).
2. Route to the matching command/skill pair from `AGENTS.md` §3 (Skill & Command Routing Matrix). Never execute skill logic without going through its command trigger.
3. For DEFINE, PLAN, and BUILD (`/perf-spec`, `/perf-plan`, `/perf-script`), act as the Master Agent (`agents/perf-architect.md`) and produce the phase's artifact directly (SLO matrix, baseline checklist, k6 script).
4. For VERIFY, AUDIT, and SHIP (`/perf-verify`, `/perf-audit`, `/perf-gate`), act as the Master Agent to execute the run and draft findings, then **spawn the `bottleneck-auditor` Sub-Agent** with the payload defined in `AGENTS.md` §4 (target SLOs, raw execution logs, Master's draft).
5. Do not output a final user-facing result for VERIFY, AUDIT, or SHIP until the Sub-Agent returns `AUDIT VERDICT: APPROVED`. On `REJECTED`, apply the Required Corrections and resubmit for another audit pass — never present a rejected draft.
6. Enforce the 7 Non-Negotiables (`CLAUDE.md` §2) at every step: never assume latency, require a clean baseline, measure before optimizing, surface assumptions, reject flawed extrapolation, require runtime evidence, and require the independent Sub-Agent audit on every telemetry-producing command.

## Common Rationalizations

| Common Agent Rationalization                                                    | Engineering Reality                                                                                                    |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| "The 1 VU run looked clean, I don't need to spawn the Sub-Agent, it'd be redundant." | The Sub-Agent audit is mandatory on every `/perf-verify`, `/perf-audit`, and `/perf-gate` pass, regardless of how clean the Master's draft looks — self-grading is exactly what the audit exists to prevent. |
| "The numbers are close enough to the SLO, I'll round it to a PASS."               | SLO compliance is judged against the raw log by an independent Sub-Agent, not rounded by the Master — any p95/p99 or error-rate breach is a `REJECTED` verdict, no exceptions. |

## Red Flags

- A `/perf-verify`, `/perf-audit`, or `/perf-gate` response reaches the user with no `[AUDIT_FEEDBACK_BLOCK]` attached.
- The Master Agent reports a `PASS`/`APPROVED` outcome that the Sub-Agent never actually rendered.
- A lifecycle phase is skipped (e.g. AUDIT run without a prior VERIFY) or re-run out of order.
- A bottleneck is claimed without runtime evidence, or a latency/throughput number is stated without a corresponding measured log line in the current session.

## Required Output Format

- Routing decisions: a one-line statement of the phase and the command/skill pair being invoked — no prose paragraph.
- Any VERIFY/AUDIT/SHIP output must include both the Master's draft evidence (ASCII `k6 summary` block or metrics table) and the Sub-Agent's `[AUDIT_FEEDBACK_BLOCK]` (see `agents/bottleneck-auditor.md`) before being presented as final.
- Explanatory prose is capped at 3-5 bullet points; all quantitative content uses Markdown tables or fenced ASCII blocks.
