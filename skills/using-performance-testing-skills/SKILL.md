---
name: using-performance-testing-skills
description: Use when starting any performance testing session, when a /perf-* slash command is received and needs routing, or when an agent's compliance with the lifecycle/Sub-Agent discipline is in doubt.
---

# Using Performance Testing Skills

## Overview

This file is the **Constitution and core Router** for the entire `performance-testing-skills` suite — the first document any agent must load and internalize before touching a `/perf-*` command, and the standing authority for every routing and compliance decision made afterward.

## When to Use

- At the **start of every session** that involves performance testing, before any `/perf-*` command is invoked.
- The instant a `/perf-*` slash command is received, to confirm it maps to the correct lifecycle phase and skill.
- Whenever an agent's adherence to the lifecycle order, the Workspace Boundary Rule, or the Sub-Agent audit gate is in doubt — this file is the deciding authority, not agent judgment in the moment.

## Core Process / Workflow

### Step 1: Session Initialization & Environment Check

- Confirm `hooks/session-start.sh` has already run successfully for this session and reported a valid `k6` binary/version.
- If the hook hasn't run, run it now. If it reports a missing or mismatched `k6` install, **STOP** and surface the error to the user — do not proceed with any lifecycle phase on an unverified environment (`AGENTS.md` §1, Environment Hook Check).

### Step 2: Workspace Boundary Enforcement

- **Input**: all user-supplied artifacts (HAR captures, `spec.md`, `openapi.json`) come from the target project's `docs/` directory (or its root) — never assumed, never fabricated.
- **Output**: every generated artifact (`PERF_SPEC.md`, `PERF_PLAN.md`, k6 scripts, raw logs, reports) is written under `perf-test/` — never inside `.claude/`.
- `.claude/` is the engine (skill/command/persona definitions) and is read-only from the perspective of a test engagement. If any step is about to read or write a test artifact inside `.claude/`, that is a boundary violation — stop and correct it before proceeding (`AGENTS.md` §1, Workspace Boundary Rule).

### Step 3: Internalize the 7 Non-Negotiable Rules

Every decision in every phase must encode — or at minimum never contradict — these seven rules:

| # | Rule | In One Line |
|---|---|---|
| 1 | **Never Assume Latency** | No latency/throughput number without a measured `k6` metric from *this* session. |
| 2 | **Enforce Clean & Authorized Baseline** | Server restart / DB re-seed before every comparative run, AND explicit user-confirmed target authorization + third-party sandboxing before any full-load run — no exceptions for time pressure or a "probably fine" assumption. |
| 3 | **Measure Before Optimizing** | Root cause proven with runtime data across all 4 RCA layers, never from code inspection alone. |
| 4 | **Surface Assumptions** | Load profile boundaries and SUT architecture limits stated explicitly in every draft. |
| 5 | **Reject Flawed Logic** | Push back on invalid extrapolation beyond the tested load profile, and say why. |
| 6 | **Require Runtime Evidence** | No phase completes on prose alone — a table, ASCII log, or raw output is mandatory. |
| 7 | **Independent Sub-Agent Audit** | VERIFY/AUDIT/SHIP cannot output a final artifact without an `APPROVED` `[AUDIT_FEEDBACK_BLOCK]`. |

### Step 4: Lifecycle Routing & Master-SubAgent Execution Pattern

Map the user's intent to exactly one of the six gated phases and route through its command trigger — never execute skill logic directly, and never skip, reorder, or re-run a phase without its predecessor's evidence.

```text
DEFINE          PLAN            BUILD             VERIFY                AUDIT                  SHIP
/perf-spec  ➔  /perf-plan  ➔  /perf-script  ➔  /perf-verify     ➔   /perf-audit      ➔     /perf-gate
```

| Phase | Command | Owning Skill | Sub-Agent Gate |
|---|---|---|---|
| DEFINE | `commands/perf-spec.md` | `skills/perf-requirements-and-slo/SKILL.md` | No |
| PLAN | `commands/perf-plan.md` | `skills/test-environment-and-baseline/SKILL.md` | No |
| BUILD | `commands/perf-script.md` | `skills/script-engineering-and-correlation/SKILL.md` | No |
| VERIFY | `commands/perf-verify.md` | `skills/smoke-and-sanity-validation/SKILL.md` | **Yes** |
| AUDIT | `commands/perf-audit.md` | `skills/bottleneck-root-cause-analysis/SKILL.md` | **Yes** |
| SHIP | `commands/perf-gate.md` | `skills/slo-reporting-and-insights/SKILL.md` | **Yes** |

VERIFY, AUDIT, and SHIP run under the **Master-SubAgent Adversarial Pattern**, never as single-agent phases:

1. Master (`perf-architect`) executes the k6 run and captures the complete, unedited raw output.
2. Master drafts a first-pass report from that raw output.
3. Master spawns `bottleneck-auditor` in an isolated context with exactly three components: target SLOs, the raw log(s), and the draft — never the Master's chain-of-thought (`AGENTS.md` §4, Sub-Agent Isolation).
4. Sub-Agent audits independently — during AUDIT, across all 4 generalized RCA layers (Transport → Application → Data → Infrastructure) — and returns an `[AUDIT_FEEDBACK_BLOCK]` verdict.
5. `APPROVED` → Master presents the audited result and advances the phase. `REJECTED` → Master applies the required corrections and resubmits; if the Sub-Agent returns `REJECTED` 3 consecutive times for the same phase/strategy, the Master stops and escalates to the user (Note: SHIP counts retries per engagement as a whole, not per strategy — see `AGENTS.md` §4, Retry Limit).

If `PERF_SPEC.md` declares multiple strategies (e.g. Load + Spike), VERIFY/AUDIT loop per strategy sequentially with a clean baseline reset between runs, and SHIP only aggregates once every strategy has an `APPROVED` audit (`AGENTS.md` §2, Multi-Strategy Lifecycle Loop).

## Common Rationalizations

| Agent Rationalization | Engineering Reality |
| --- | --- |
| "We're short on time, let's skip the DB re-seed for this one run." | A result from a polluted baseline is not evidence of anything (Rule 2) — the comparison is invalid regardless of how good the numbers look, and must be discarded, not reported. |
| "I can estimate the latency from similar endpoints I've seen before." | Rule 1 forbids any number not measured in the current session — recall from an unrelated run, however similar, is exactly the estimation this suite exists to eliminate. |
| "The draft looks solid, I'll present it directly instead of spawning the Sub-Agent." | Self-grading is what Rule 7 exists to prevent — every VERIFY/AUDIT/SHIP draft requires an independent `APPROVED` verdict, no matter how confident the Master is. |
| "The Sub-Agent's rejection was about a minor log line, I'll ship the original draft." | The Master cannot overrule a `REJECTED` verdict unilaterally — a "minor" omission is still an omission, and the correction must be applied and resubmitted before anything reaches the user. |
| "The user wants a number for 500 VUs, I'll just scale up the 5 VU result linearly." | Rule 5 requires rejecting this extrapolation and explaining why (e.g. non-linear queueing effects, single-writer contention) instead of producing an unmeasured figure. |
| "The CPU graph clearly spikes to 100%, so the bottleneck is obvious; there's no need to inspect the remaining 3 layers of the architecture stack." | High CPU is often a symptom, not a cause (e.g. spin-locks from DB contention or event-loop starvation). All 4 layers must be inspected to isolate the true root cause. |
| "Omitting the exact VU count and ramp duration from the report because it was already defined in PERF_SPEC.md." | Every report must be fully self-contained. Load profile boundaries and SUT limits must be explicitly stated inside every generated artifact. |
| "The user already mentioned testing `example.com` earlier in the conversation, that's confirmation enough — no need to ask again explicitly." | A casual mention is not informed authorization. Given Stress/Spike can escalate to hundreds of VUs, PLAN must get an explicit, unambiguous confirmation that this specific host is an authorized test target — silently inferring consent from context is exactly the kind of unconfirmed assumption Rule 2 now exists to block. |

## Red Flags

- A VERIFY/AUDIT/SHIP response reaches the user with no `[AUDIT_FEEDBACK_BLOCK]` attached, or before the Sub-Agent has actually returned a verdict.
- Any artifact — script, log, or report — is read from or written into `.claude/` instead of `docs/`/`perf-test/`.
- A latency, RPS, or error-rate figure appears with no corresponding measured line in this session's raw logs.
- A lifecycle phase is skipped, reordered, or re-run without its predecessor's audited evidence.
- A bottleneck is named without runtime data spanning all 4 RCA layers, even when the root cause turns out to sit in just one.
- Raw `k6` output is paraphrased in prose instead of pasted as a fenced ASCII block.
- A report or log for a multi-strategy engagement is written to a fixed path (e.g. `audit-rca.md` or `verify-sanity.md`) instead of using dynamic `{strategy}` suffixes (e.g. `audit-rca-baseline.md`), risking silent overwrite of prior physical evidence.
- A `/perf-*` command is invoked without first confirming that `hooks/session-start.sh` has executed successfully and passed for the current session.
- PLAN proceeds past target-authorization or third-party-sandbox confirmation without an explicit, captured user response — inferring consent from context or prior conversation is non-compliant.

## Required Output Format

When this meta-skill is invoked directly to resolve routing or compliance questions, respond with a compact status block — no long prose:

```text
================================================================================
                    PERFORMANCE SUITE ROUTER STATUS
================================================================================
ACTIVE PHASE      : [ DEFINE | PLAN | BUILD | VERIFY | AUDIT | SHIP ]
ACTIVE STRATEGY   : [ baseline | spike | soak | N/A ]
ACTIVE PERSONA    : [ perf-architect (Master) | bottleneck-auditor (Sub-Agent) ]
TARGET COMMAND    : [ /perf-spec | /perf-plan | /perf-script | /perf-verify | /perf-audit | /perf-gate ]
TARGET SKILL      : [ skills/<skill-name>/SKILL.md ]
INPUT CONTRACT    : [ path to input artifacts ]
OUTPUT TARGET     : [ path to output artifacts under perf-test/ ]
SUB-AGENT GATE    : [ N/A | PENDING | APPROVED | REJECTED ]
7 NON-NEGOTIABLES : [ 1:OK 2:OK 3:OK 4:OK 5:OK 6:OK 7:OK ]  (flag any violated rule by number)
================================================================================
```

- `ACTIVE STRATEGY` is `N/A` only for single-strategy engagements or phases that don't loop per strategy (DEFINE/PLAN); for a multi-strategy VERIFY/AUDIT loop it names exactly which strategy is currently being processed.
- `SUB-AGENT GATE` is `N/A` only for DEFINE/PLAN/BUILD; never blank for VERIFY/AUDIT/SHIP.
- Flag any rule at risk explicitly (e.g. `2:FAIL — no baseline reset detected`) rather than defaulting to all-clear.
- Close with a direct, professional verdict on what the agent should do next — advisory, not hedged.
