---
name: smoke-and-sanity-validation
description: Use when executing 1 VU sanity dry-runs (30s), validating script correctness before full load, running Sub-Agent Audit Gate 1, or writing perf-test/reports/verify-sanity-{strategy}.md.
---

# Smoke and Sanity Validation

## Overview

Executes a 1 VU / 30s dry-run of the k6 script under test to confirm it runs cleanly — no script logic errors, no silently-failing checks, no misconfigured thresholds — before any full load run is attempted. This is the **first phase that triggers the Sub-Agent Audit Gate** (Gate 1, `bottleneck-auditor`); the Master's draft never reaches the user unaudited.

## When to Use

- The `/perf-verify` command is invoked.
- Immediately after BUILD (`/perf-script`) produces `perf-test/scripts/{strategy}.k6.js` for a given strategy.
- Before every full-load AUDIT run for that strategy — VERIFY must pass with an `APPROVED` verdict first.
- For every strategy in a multi-strategy engagement the first time that strategy is run — each declared strategy gets its own independent VERIFY pass.

## Core Process / Workflow

1. **Baseline Verification & Pre-flight Check.** Read `perf-test/PERF_PLAN.md`. For the first strategy in the engagement, confirm its row in the Clean Baseline Verification Checklist is `PASS` with restart/re-seed/idle evidence attached. **For the second and every subsequent strategy in the Multi-Strategy loop, that strategy's row MUST have moved from `PENDING` to `PASS` with fresh restart/re-seed/idle evidence specific to this run** (`test-environment-and-baseline/SKILL.md`, Clean Baseline Enforcement). **If that strategy's row is still `PENDING` or shows stale/reused evidence, STOP and require a fresh baseline reset before continuing — the Master agent (still acting as `perf-architect`) MUST execute the reset procedure per `test-environment-and-baseline/SKILL.md` §3 and update that row in `perf-test/PERF_PLAN.md` to `PASS` with fresh evidence before resuming this step.**
2. **1 VU Sanity Execution & Raw Log Capture.** Run `perf-test/scripts/{strategy}.k6.js` at 1 VU for 30 seconds. Capture the **complete, unedited** raw CLI output and persist it to `perf-test/logs/{strategy}-verify.log` (e.g. `perf-test/logs/baseline-verify.log`) — never trim, summarize, or paraphrase away lines before they are logged. Optional: if `perf-test/observability/docker-compose.yml` exists, ask the user a single light question — "Is the observability stack currently running?" — no STOP, no escalation either way. If confirmed running, add `--out experimental-prometheus-rw --tag testid={strategy}-verify-{timestamp}` to the k6 command (per `references/observability-stack-setup.md` §5); if not confirmed, run the command exactly as before with no changes. This flag never alters what gets captured into `perf-test/logs/{strategy}-verify.log` — the raw log capture requirement is identical either way.
3. **Master Draft Generation.** From the raw log captured in Step 2, draft the Sanity Execution Summary and the Checks vs. Thresholds breakdown, with an explicit tally of any failed checks or breached thresholds — never a bare "all good" claim with no numbers behind it.
4. **Sub-Agent Gate 1 Submission & Report Persistence.** Assemble the payload — **exactly 3 clean components**: target SLOs from `perf-test/PERF_SPEC.md`, the raw `perf-test/logs/{strategy}-verify.log`, and the Master's draft — and spawn `bottleneck-auditor` via the Task tool in an isolated context (never the Master's own reasoning turn, never leaking chain-of-thought). On `AUDIT_VERDICT: REJECTED`, apply the `REQUIRED_CORRECTIONS` exactly and resubmit a revised draft for a fresh audit pass; **after 3 consecutive `REJECTED` verdicts for this same strategy, stop the retry loop and escalate directly to the user** with all 3 verdicts and their contradictions (`AGENTS.md` §4, Retry Limit). On `AUDIT_VERDICT: APPROVED`, persist the audited result to `perf-test/reports/verify-sanity-{strategy}.md` — a report file must never be written from an un-audited draft.

## Common Rationalizations

| Common Agent Rationalization | Engineering Reality |
| --- | --- |
| "It's just a 1 VU dry-run, it doesn't need to go through Sub-Agent audit." | Gate 1 is exactly where cheap defects (bad checks, misconfigured thresholds, leaked credentials) get caught before expensive full-load VUs are wasted running a broken script — the audit gate applies to every VERIFY draft, not just full-load AUDIT drafts. |
| "It's only 1 VU, I'll skip checking the baseline row in `PERF_PLAN.md` for this strategy." | A 1 VU run against an unreset environment can still read stale in-memory state or polluted DB rows left by a prior strategy's run — the baseline check is not proportional to VU count. |
| "I'll overwrite `verify-sanity.md` instead of using the `{strategy}` suffix, it's simpler." | A fixed filename silently destroys the previous strategy's persisted evidence the moment the next strategy's VERIFY runs — every report requires its explicit `{strategy}` suffix, no exceptions. |
| "The draft looks clean, I'll present it now and let the Sub-Agent audit run in parallel." | Self-review-while-presenting is exactly the pattern the Gate 1 isolation protocol exists to prevent — the user only sees the result after `AUDIT_VERDICT: APPROVED` comes back, never before. |
| "The Sub-Agent rejected over one skipped check, I'll ship the original draft — it's a minor thing." | The Master cannot overrule a `REJECTED` verdict, however minor it looks — apply the `REQUIRED_CORRECTIONS` and resubmit for a fresh audit pass. |
| "I'll include my reasoning for why the script is correct in the Sub-Agent payload, it'll help the audit." | The payload is limited to exactly 3 components (SLOs, raw log, draft) — the Master's chain-of-thought must never be passed in, since it would bias the "independent" verdict. |
| "I'll just run `docker compose up -d` myself to save the user a step." | Running the observability stack is exclusively the user's manual action — the agent's role stops at generating a correct, runnable file. Starting a background Docker daemon process without explicit, in-the-moment user execution crosses outside what this suite's agents are scoped to do. |

## Red Flags

- VERIFY executes for a second-or-later strategy without confirming that strategy's Clean Baseline Verification Checklist row in `PERF_PLAN.md` moved from `PENDING` to a fresh `PASS`.
- `perf-test/logs/{phase}-verify.log` or `perf-test/reports/verify-sanity-{phase}.md` is written to a fixed/generic filename instead of the `{strategy}`-suffixed convention.
- A VERIFY result is shown to the user, or persisted to `perf-test/reports/`, with no `AUDIT_VERDICT: APPROVED` attached for that exact draft.
- The Sub-Agent payload contains anything beyond the 3 admissible components — in particular, any trace of the Master's chain-of-thought or reasoning narrative.
- The retry loop continues past 3 consecutive `REJECTED` verdicts for the same strategy without stopping and escalating to the user.
- A failed check or breached threshold from the raw log is omitted or downplayed in the Master's draft.
- The agent executes any `docker`/`docker compose` command itself instead of only generating the configuration files and instructing the user to run them.

## Required Output Format

Persist `perf-test/reports/verify-sanity-{strategy}.md` in this shape — metadata header, sanity execution summary, checks/thresholds breakdown, then the attached audit block:

````markdown
# verify-sanity-{strategy}.md

## Metadata
- Strategy: baseline
- Phase: VERIFY (Sub-Agent Audit Gate 1)
- Script: perf-test/scripts/baseline.k6.js
- Baseline Reset Reference: PERF_PLAN.md Clean Baseline Verification Checklist row "Load (baseline)" — PASS
- Machine Reference: PERF_PLAN.md Environment Parity Summary — {{CPU_MODEL}}, {{TOTAL_RAM_GB}}GB RAM

## Sanity Execution Summary

```text
     execution: local
        vus: 1  duration: 30s
     iterations..............: 14      0.47/s
     http_req_duration.......: avg=210ms min=180ms max=310ms p95=295ms
     http_req_failed.........: 0.00%  0 out of 14
```

## Checks vs Thresholds Breakdown

| Check/Threshold                  | Result | Detail                        |
|------------------------------------|:------:|---------------------------------|
| status is 200                        | PASS   | 14/14 iterations                |
| checkout total matches cart total    | PASS   | 14/14 iterations                |
| http_req_duration: p(95)<500         | PASS   | measured p95 = 295ms            |

## [SUB-AGENT ADVERSARIAL AUDIT REPORT]

```text
================================================================================
                     SUB-AGENT ADVERSARIAL AUDIT REPORT
================================================================================
AUDIT_VERDICT      : APPROVED
RAW_LOG_CHECK      : Independently counted 14 requests, 0 errors
SLO_COMPLIANCE     : POST /api/checkout: p95 295ms vs 500ms target -> PASS
BYPASSED_ERRORS    : None found
REQUIRED_CORRECTIONS: None — cleared for release.
================================================================================
```
````

- The `Baseline Reset Reference` line in the report's Metadata header MUST cite the exact row in `PERF_PLAN.md` that carries a `PASS` status with fresh execution evidence for this strategy — referencing a `PENDING`, unreset, or stale row is non-compliant.
- The `Machine Reference` line MUST cite `PERF_PLAN.md`'s Environment Parity Summary Host Machine Specification for this session — never left blank and never typed independently of what `PERF_PLAN.md` already records.
- The `[SUB-AGENT ADVERSARIAL AUDIT REPORT]` block is mandatory and must be pasted verbatim from `bottleneck-auditor`'s output — never paraphrased or reconstructed by the Master.
- Every row in the Checks vs Thresholds Breakdown must show a real `PASS`/`FAIL` result traceable to the raw log, never an assumed default.
- Prose outside the tables/blocks is capped at 3-5 bullet points.
