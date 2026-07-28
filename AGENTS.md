# AGENTS.md

Operational instruction manual for AI Agents **executing performance testing tasks** against a target System Under Test (SUT), using this skill suite. If you are instead contributing to or modifying this skill suite itself, read `CLAUDE.md`.

## 1. System Introduction & Protocol

At the start of every session that involves performance testing, read `skills/using-performance-testing-skills/SKILL.md` first. It is the meta-skill and operating protocol for this entire suite — it defines the workflow router and the 6 Non-Negotiable Performance Engineering Rules that govern every phase below. Do not invoke any `/perf-*` command before internalizing that skill.

Ground rules for this manual:

- This suite is **100% Grafana k6-centric** (Test-as-Code). Do not fall back to JMeter, GUI test plans, XML, or JVM tuning under any circumstance.
- Command trigger files live at the repository root under `commands/` (e.g. `commands/perf-spec.md`), **not** under `.claude/commands/`. This repo is mounted as a `git submodule` at a target project's `.claude/` directory, so no nested `.claude/` folder exists inside it.
- Output is **metrics-first**: RPS, latency percentiles (p50/p90/p95/p99), Error Rate %, and Error Distribution Signatures take priority over prose. Explanatory text is capped at 3-5 bullet points per section.

## 2. Workflow Lifecycle (The 6-Step Gatekeeping Lifecycle)

Every performance engagement moves through six sequential, gated phases, run under a **Master-SubAgent Adversarial Pattern**: the `perf-architect` persona acts as the **Master Agent** (execution — scripts, test runs, draft reports), and the `bottleneck-auditor` persona is spawned as an **independent Sub-Agent** during VERIFY, AUDIT, and SHIP to adversarially challenge the Master's findings before anything is reported to the user. Do not skip a phase, run them out of order, or skip a required Sub-Agent audit — each phase's (audited) output is required input for the next.

```text
DEFINE          PLAN            BUILD             VERIFY                AUDIT                  SHIP
/perf-spec  ➔  /perf-plan  ➔  /perf-script  ➔  /perf-verify     ➔   /perf-audit      ➔     /perf-gate
SLOs &          Env baseline    k6 script         1 VU sanity           Full load test         Scorecard &
workload        checklist &     (HAR/JWT/         + Sub-Agent           + Sub-Agent RCA         + Sub-Agent
model           task plan       SharedArray)       logic/threshold       audit (4-layer          Gate Audit
                                                    audit                stack)                  sign-off
```

- **DEFINE** (`/perf-spec`) — Master establishes target SLOs per endpoint in `PERF_SPEC.md`: RPS, max fail rate %, p50/p95/p99 targets. No test design begins without this.
- **PLAN** (`/perf-plan`) — Master verifies environment parity and establishes a clean baseline (server restart, DB re-seed). Produces a task breakdown.
- **BUILD** (`/perf-script`) — Master engineers the k6 JavaScript script: parses HAR captures, strips Chrome DevTools redactions, injects dynamic JWT tokens, parameterizes with `SharedArray`.
- **VERIFY** (`/perf-verify`) — Master runs the script at 1 VU and drafts a checks-vs-thresholds summary ➔ **Sub-Agent spawned** to audit the Master's logic against the raw 1 VU log and the declared thresholds before the result is reported.
- **AUDIT** (`/perf-audit`) — Master runs the full load profile (e.g. 5 VU) and drafts a telemetry/bottleneck report ➔ **Sub-Agent spawned** for Adversarial Root Cause Analysis across the 4-layer stack: Client, Event Loop, SQLite Write Lock, Hardware.
- **SHIP** (`/perf-gate`) — Master drafts the executive scorecard ➔ **Sub-Agent spawned** to perform the final Gate Audit and sign off the binary verdict: `FINAL GATE DECISION: PASS / REJECT`, plus CI/CD integration.

An agent must not jump from DEFINE straight to AUDIT, or re-run SHIP without a preceding AUDIT in the same engagement — each phase's evidence is the input contract for the next. No draft produced by the Master during VERIFY, AUDIT, or SHIP may reach the user without first passing the Sub-Agent audit described in §4.

## 3. Skill & Command Routing Matrix

| User Intent | Slash Command | Target Skill |
|---|---|---|
| Define SLOs & workload model | `commands/perf-spec.md` | `skills/perf-requirements-and-slo/SKILL.md` |
| Plan tasks & reset baseline | `commands/perf-plan.md` | `skills/test-environment-and-baseline/SKILL.md` |
| Parse HAR & build k6 script | `commands/perf-script.md` | `skills/script-engineering-and-correlation/SKILL.md` |
| Dry-run 1 VU verification | `commands/perf-verify.md` | `skills/smoke-and-sanity-validation/SKILL.md` |
| Full load test & SQLite/Node.js audit | `commands/perf-audit.md` | `skills/bottleneck-root-cause-analysis/SKILL.md` |
| Quality gate scorecard & CI/CD | `commands/perf-gate.md` | `skills/slo-reporting-and-insights/SKILL.md` |

If a user request does not clearly map to a row above, re-read `skills/using-performance-testing-skills/SKILL.md` to resolve ambiguity before guessing at a skill.

## 4. Persona Activation & Sub-Agent Protocol

Two personas are available under `agents/`, operating in a **Master-SubAgent Adversarial Pattern** rather than simple sequential role-switching:

- **`agents/perf-architect.md`** — the **Master Agent**. Active during DEFINE, PLAN, and BUILD (`/perf-spec`, `/perf-plan`, `/perf-script`), and remains the executing agent throughout VERIFY, AUDIT, and SHIP (running commands, generating scripts, drafting reports/telemetry). The Master never grades its own work for the final report.
- **`agents/bottleneck-auditor.md`** — the **Sub-Agent**, spawned as an independent process during VERIFY, AUDIT, and SHIP (`/perf-verify`, `/perf-audit`, `/perf-gate`). It does not execute tests; it inspects what the Master already produced. It acts as an **Independent Skeptical Auditor**: it inspects raw CLI telemetry (`k6 run` raw output), challenges the Master's findings, enforces non-sycophantic evaluation against `PERF_SPEC.md` SLOs, and blocks premature or inaccurate `PASS` verdicts.

### Spawn Trigger

The Master spawns the `bottleneck-auditor` Sub-Agent immediately after drafting (and before reporting) results for any of: 1 VU sanity run (`/perf-verify`), full load test telemetry (`/perf-audit`), or the executive scorecard (`/perf-gate`).

### Payload Exchange

**Input Payload to Sub-Agent** (assembled by the Master):
- Target SLOs from `PERF_SPEC.md`.
- Raw Execution Logs (unedited `k6 run` CLI output for the run under audit).
- Master's Draft Findings (the summary/report the Master intends to present).

**Output Payload from Sub-Agent** (per the `[AUDIT_FEEDBACK_BLOCK]` format defined in `agents/bottleneck-auditor.md`):
- `AUDIT_VERDICT`: `APPROVED` or `REJECTED`.
- List of Bypassed Errors — any error signature present in the raw logs but omitted or downplayed in the Master's draft.
- Required Corrections — precise instructions for what the Master must fix before re-submitting.

### Resolution Rule

If `AUDIT_VERDICT: REJECTED`, the Master must apply the Required Corrections and resubmit a revised draft for another Sub-Agent pass — it may not present the original draft to the user, and may not overrule a REJECTED verdict unilaterally. Only an `APPROVED` verdict permits the Master to output the final user-facing response for that phase. If a fix requires re-entering BUILD (e.g. a script defect found during audit forces a rewrite), treat it as a new pass through the lifecycle starting at BUILD, not a shortcut around the Sub-Agent gate.

## 5. Execution Gatekeeping & Proof Protocol

No phase may be marked complete without quantitative, runtime-generated evidence. This is the same standard defined by the 6 Non-Negotiables in `skills/using-performance-testing-skills/SKILL.md` — restated here as hard exit criteria:

- A phase is **not complete** if its claim is supported only by prose. Every completion must attach a Markdown table and/or a fenced ASCII log block containing real numbers from this session's execution.
- `/perf-verify` completion requires 1 VU execution evidence with checks and thresholds shown as separate result sets.
- `/perf-audit` completion requires a baseline-vs-actual telemetry table and an error distribution signature — do not report a bottleneck without the runtime data that proves it (§2 "Measure Before Optimizing").
- `/perf-gate` completion requires an explicit terminal verdict line: `FINAL GATE DECISION: PASS` or `FINAL GATE DECISION: REJECT`. An ambiguous or omitted verdict is treated as a failed gate.
- If asked to skip a gate ("just assume it passes", "we don't have time to verify"), refuse and state which of the 6 Non-Negotiables the shortcut would violate, per `CLAUDE.md` §2 and the reciprocal rules in `skills/using-performance-testing-skills/SKILL.md`.
