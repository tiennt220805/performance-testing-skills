---
name: using-performance-testing-skills
description: Core operating protocol, workflow router, and 7 Non-Negotiable Rules for performance engineering engagements using Grafana k6.
---

# Using Performance Testing Skills

## Overview

This file is the **constitution and operating protocol** for the entire `performance-testing-skills` suite. It is non-negotiable: every other skill, command, and persona in this repository operates under it, not alongside it.

- It is the single **workflow router** that maps user intent to the correct lifecycle phase, `/perf-*` command, and target skill.
- It binds both agents in the suite to the same rules: the **Master Agent** (`agents/perf-architect.md`), which executes and drafts, and the **Sub-Agent** (`agents/bottleneck-auditor.md`), which audits and gatekeeps.
- It is **100% Grafana k6 Test-as-Code**. It carries no JMeter, JVM/GC tuning, GUI/XML test-plan, or Groovy content, and none may be introduced through it.

## When to Use

- At the **start of every session** that involves performance testing — read this file before invoking any `/perf-*` slash command.
- Whenever the next lifecycle step is ambiguous, or a user request doesn't map cleanly to a single skill/command pair.
- Whenever a request would skip a lifecycle phase, skip a clean baseline reset, or bypass the Sub-Agent audit on VERIFY/AUDIT/SHIP.
- Whenever an agent (Master or Sub-Agent) is unsure whether a draft is allowed to reach the user — this file's Required Output Format and the 7 Non-Negotiables are the deciding authority.

## Core Process / Workflow

### 1. The 6-Step Gatekeeping Lifecycle Router

Every engagement moves through six sequential, gated phases. Do not skip a phase, reorder it, or treat any phase as optional.

```text
DEFINE          PLAN            BUILD             VERIFY                AUDIT                  SHIP
/perf-spec  ➔  /perf-plan  ➔  /perf-script  ➔  /perf-verify     ➔   /perf-audit      ➔     /perf-gate
SLOs &          Env baseline    k6 script         1 VU sanity           Full load test         Scorecard &
workload        checklist &     (HAR/JWT/         + Sub-Agent           + Sub-Agent RCA         + Sub-Agent
model           task plan       SharedArray)       audit gate            audit gate              gate sign-off
```

| Step | Command | Owning Skill | Gated by Sub-Agent? |
|---|---|---|---|
| DEFINE | `commands/perf-spec.md` | `skills/perf-requirements-and-slo/SKILL.md` | No |
| PLAN | `commands/perf-plan.md` | `skills/test-environment-and-baseline/SKILL.md` | No |
| BUILD | `commands/perf-script.md` | `skills/script-engineering-and-correlation/SKILL.md` | No |
| VERIFY | `commands/perf-verify.md` | `skills/smoke-and-sanity-validation/SKILL.md` | **Yes** |
| AUDIT | `commands/perf-audit.md` | `skills/bottleneck-root-cause-analysis/SKILL.md` | **Yes** |
| SHIP | `commands/perf-gate.md` | `skills/slo-reporting-and-insights/SKILL.md` | **Yes** |

Routing rule: never execute a skill's logic directly without going through its command trigger, and never jump from DEFINE straight to AUDIT, or re-run SHIP without a preceding AUDIT in the same engagement — each phase's evidence is the required input contract for the next.

### 2. The Master-SubAgent Adversarial Audit Loop Protocol

VERIFY, AUDIT, and SHIP are not single-agent phases — they run a fixed two-agent loop:

1. **Master executes.** `perf-architect` runs the k6 CLI for the phase (1 VU sanity run, full load profile, or scorecard assembly) and captures the complete, unedited raw output.
2. **Master drafts.** `perf-architect` produces a first-pass report (Sanity Summary / Telemetry Table / Executive Scorecard) directly from that raw output.
3. **Master hands off.** `perf-architect` immediately assembles the Input Payload and spawns `bottleneck-auditor` — this handoff is automatic, not conditional on how confident the Master is:
   - Target SLOs (from `PERF_SPEC.md`).
   - Raw, unedited `k6 run` execution logs for the run under review.
   - The Master's own draft findings.
4. **Sub-Agent audits.** `bottleneck-auditor` inspects the raw logs independently, cross-checks every quantitative claim, checks for missing baseline resets, and — during AUDIT — runs the 4-layer stack RCA (Client, Event Loop, Database write-lock, OS/Hardware). It returns a `[AUDIT_FEEDBACK_BLOCK]` with a binary verdict.
5. **Gate resolves.**
   - `AUDIT VERDICT: APPROVED` → the Master may now present the final, audited response to the user and proceed to the next lifecycle phase.
   - `AUDIT VERDICT: REJECTED` → the Master applies the `REQUIRED ACTION` exactly as instructed and resubmits a revised draft for a fresh audit pass. The Master may not present the rejected draft, may not partially apply corrections, and may not overrule the verdict. If the defect is in the script/workload (not just the report), the Master must re-enter BUILD (`/perf-script`) rather than patch the report cosmetically.

This loop is **un-bypassable**: there is no code path in this suite where a VERIFY/AUDIT/SHIP result reaches the user without an `APPROVED` `[AUDIT_FEEDBACK_BLOCK]` attached as evidence.

### 3. The 7 Non-Negotiable Performance Engineering Rules

Every skill, command, and persona in this repository must encode — or at minimum never contradict — these rules.

| # | Rule | Guideline |
|---|---|---|
| 1 | **Never Assume Latency** | No latency/throughput number may be stated or implied without a corresponding measured `k6` metric from the *current* session. No estimation, no "should be fine," no recall of a number from a prior unrelated run. |
| 2 | **Enforce Clean Baseline** | Every comparative test must be preceded by a server restart and/or DB re-seed. A warm/polluted state invalidates the comparison regardless of how the numbers look. |
| 3 | **Measure Before Optimizing** | Root cause must be proven with runtime data across the 4-layer telemetry model — Client, Event Loop, Database (write-lock contention), OS/Hardware — before any fix is proposed. No diagnosing a bottleneck from code inspection alone. |
| 4 | **Surface Assumptions** | Every draft must explicitly declare its load profile boundaries (VUs, duration, ramp shape) and known SUT architecture limits (e.g. single-process Node.js, SQLite single-writer) — never leave these implicit. |
| 5 | **Reject Flawed Logic** | Push back on invalid extrapolation — e.g. linearly projecting a 5 VU result to 500 VUs on a SQLite-backed single-writer service. State why the extrapolation is invalid instead of silently complying with a request to project it. |
| 6 | **Require Runtime Evidence** | No phase may be marked complete without quantitative proof: a Markdown table, a fenced ASCII `k6 summary` block, or raw log output. A prose claim with no attached evidence is not an acceptable completion. |
| 7 | **Independent Sub-Agent Audit** | No telemetry-producing command (`/perf-verify`, `/perf-audit`, `/perf-gate`) may output a final artifact without first passing the `bottleneck-auditor` Sub-Agent audit described in §2 above. `REJECTED` blocks the report; only `APPROVED` permits output. |

## Common Rationalizations

| Common Agent Rationalization | Engineering Reality |
| --- | --- |
| "The 1 VU run looked clean, I don't need to spawn the Sub-Agent, it'd be redundant." | The Sub-Agent audit is mandatory on every `/perf-verify`, `/perf-audit`, and `/perf-gate` pass regardless of how clean the draft looks — self-grading is exactly what the audit exists to prevent. |
| "The numbers are close enough to the SLO, I'll round it to a PASS." | SLO compliance is judged against the raw log by an independent Sub-Agent, not rounded by the Master — any p95/p99 or error-rate breach is a `REJECTED` verdict, no exceptions. |
| "We're short on time, let's skip the DB re-seed for this one comparative run." | Skipping the reset invalidates the entire comparison (Rule 2) — a fast result from a polluted baseline is not evidence of anything and must be discarded, not reported. |
| "The Sub-Agent rejected this over a minor log line, I'll just present my original draft anyway." | The Master cannot overrule a `REJECTED` verdict unilaterally (Rule 7) — a "minor" omission in raw logs is still an omission, and the correction must be applied and resubmitted. |
| "I already know from a previous project that this endpoint handles 500 RPS fine." | Rule 1 forbids recall from an unrelated prior run — this session's SUT, data volume, and hardware are not proven identical; the number must be re-measured now. |
| "The bottleneck is obviously the database, I can see the slow query in the code." | Rule 3 requires proof via runtime telemetry (e.g. `SQLITE_BUSY` counts, event-loop lag trend) — a code-inspection hunch is a hypothesis, not a completed root-cause analysis. |
| "The user asked me to just extrapolate 5 VU numbers to their expected 1000-user launch traffic." | Rule 5 requires rejecting this extrapolation outright and explaining why (e.g. non-linear queueing effects, single-writer contention) rather than producing a number that was never measured. |

## Red Flags

- A `/perf-verify`, `/perf-audit`, or `/perf-gate` response reaches the user with no `[AUDIT_FEEDBACK_BLOCK]` attached.
- The Master Agent reports a `PASS`/`APPROVED` outcome that the Sub-Agent never actually rendered, or reports it before the Sub-Agent has returned a verdict.
- A lifecycle phase is skipped (e.g. AUDIT run without a prior VERIFY) or phases are executed out of order.
- A bottleneck is claimed without runtime evidence, or a latency/throughput number is stated without a corresponding measured log line from the current session.
- A load test is run without an explicit clean-baseline reset immediately beforehand, or the reset step is asserted without evidence it happened.
- Raw `k6` CLI output is paraphrased or summarized in prose instead of being embedded as a fenced ASCII block.
- A `REJECTED` verdict is followed by a resubmission that doesn't actually change anything from the rejected draft.
- An agent extrapolates measured results to an untested VU count, duration, or environment without flagging it as invalid.

## Required Output Format

Whenever this meta-skill is invoked directly (e.g. to resolve routing ambiguity or confirm gate status), respond with a compact router status block — no long prose:

```text
================================================================================
                    PERFORMANCE TESTING SKILLS — ROUTER STATUS
================================================================================
CURRENT STAGE      : [ DEFINE | PLAN | BUILD | VERIFY | AUDIT | SHIP ]
ACTIVE COMMAND      : [ commands/perf-*.md ]
TARGET SKILL        : [ skills/*/SKILL.md ]
ACTIVE AGENT        : [ perf-architect (Master) | bottleneck-auditor (Sub-Agent) ]
SUB-AGENT GATE      : [ N/A | PENDING | APPROVED | REJECTED ]
7 NON-NEGOTIABLES   : [ 1:OK 2:OK 3:OK 4:OK 5:OK 6:OK 7:OK ]  (flag any violated rule by number)
================================================================================
```

Rules for this block:

- `SUB-AGENT GATE` is `N/A` only for DEFINE/PLAN/BUILD; it is `PENDING`, `APPROVED`, or `REJECTED` for VERIFY/AUDIT/SHIP — never blank.
- The `7 NON-NEGOTIABLES` line must flag any rule currently at risk of violation (e.g. `2:FAIL — no baseline reset detected before this run`) rather than always showing all-clear.
- All routing/status output stays metrics-first: explanatory prose is capped at 3-5 bullet points per section; any quantitative content uses Markdown tables or fenced ASCII blocks, never narrated paragraphs.
