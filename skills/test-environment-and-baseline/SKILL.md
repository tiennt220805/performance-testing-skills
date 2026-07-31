---
name: test-environment-and-baseline
description: Use when planning performance tasks, verifying environment parity, enforcing clean baseline resets (server restart + DB re-seed), or writing perf-test/PERF_PLAN.md.
---

# Test Environment and Baseline Verification

## Overview

Establishes a clean, representative environment baseline and the task plan for the remaining lifecycle before any k6 script is written or executed, persisting the result to `perf-test/PERF_PLAN.md`. Owned and executed directly by the Master Agent (`perf-architect`); no Sub-Agent audit gate applies to PLAN (`N/A`).

## When to Use

- The `/perf-plan` command is invoked.
- Immediately after `perf-test/PERF_SPEC.md` exists (produced or updated by `/perf-spec`), before `/perf-script` is invoked.
- Before every load test run that will be compared against a prior run or against SLOs — a comparison against an unverified environment is meaningless.
- Whenever a prior test run is suspected to have polluted the database or left server processes in a non-default state.

## Core Process / Workflow

1. **Input Contract Verification.** Read `perf-test/PERF_SPEC.md` to extract the Target SUT Stack, Target SLOs, and Declared Test Strategy list from its Engagement Metadata header. **If `perf-test/PERF_SPEC.md` does not exist, STOP immediately and instruct the user to run `/perf-spec` first — never plan against a spec that hasn't been established** (`AGENTS.md` §2, DEFINE precedes PLAN).
2. **Target Authorization & Third-Party Sandbox Gate (Non-Negotiable 2).** Before any baseline reset or environment check, confirm the engagement is safe to test at all:
   - Determine the target host actually under test — from the HAR capture's host, the OpenAPI `servers` field, or an explicit value the user has supplied. If none of these resolve a host, ask the user directly.
   - **STOP and require an explicit, unambiguous confirmation from the user** that this host is an authorized test/staging/pre-production environment they own or have explicit permission to load-test — this MUST be a direct human response in this conversation, never inferred from context, never self-approved by the Master reasoning "this looks like a staging URL." A `staging.` subdomain or `.test` TLD is a *hint*, not proof of authorization.
   - Apply a heuristic red-flag scan on the host regardless of the user's framing: no staging/dev/test-like marker in the subdomain or path, a domain that doesn't match anything else declared in `PERF_SPEC.md`/`docs/`, or a bare production-sounding root domain — if any of these trip, escalate the confirmation request explicitly instead of proceeding on an initial "yes."
   - For every `In-Scope Route` (from `PERF_SPEC.md`) that calls a third-party integration — payment gateway, SMS/OTP provider, email/notification service, external webhook — confirm with the user that a sandbox/test-mode/mock credential is configured for that integration. **If the user cannot confirm this for any such route, STOP and name exactly which route is blocking** — do not proceed to a full-load AUDIT that could hit a live third-party service at hundreds of requests per second.
   - Record both confirmations as captured evidence in `PERF_PLAN.md` (see Required Output Format) — a confirmation that was asked about but never written down does not satisfy Non-Negotiable 6 (Require Runtime Evidence applies to human confirmations exactly as it applies to measured metrics: no record, not complete).
   - **This is the one gate in the entire suite that cannot be satisfied by automated measurement.** Every other check in this file (idle CPU, restart evidence, re-seed evidence) is verified from command output the Master captures itself; this one requires a captured, direct response from the user in this conversation — the Master must not substitute its own judgment call for that response, no matter how confident it is that the target "looks like" a safe environment.
3. **Clean Baseline Enforcement (Non-Negotiable 2).** Every comparative run requires, immediately before execution:
   - A full server process restart (kill and relaunch the SUT process — never rely on a hot reload or a long-running process retaining prior in-memory state).
   - A database re-seed to a known, deterministic state (clear polluted tables or rebuild the database file from a fixture/schema script).
   - An **Idle Baseline measurement** captured right after restart and before any load: CPU utilization **< 5%**, RSS/RAM holding steady (not still climbing from a cold-start allocation spike), and no competing background cron jobs or scheduled tasks running on the SUT host.
   - Do not proceed to `/perf-script` or a load run until all three steps above have been executed and their output captured as evidence — a restart/re-seed/idle-check that is merely claimed, without a captured log line proving it ran, does not satisfy this rule.
   - **This checklist is a reusable procedure, not a one-off static record.** While `/perf-plan` itself is invoked only once, every subsequent strategy declared in `PERF_SPEC.md` requires a fresh, independent baseline reset before its VERIFY/AUDIT pass begins. The `perf-architect` Master Agent MUST execute a fresh server restart + DB re-seed + idle check, and append/update the fresh execution evidence into `PERF_PLAN.md`'s strategy-aware checklist table (see Required Output Format) before initiating that strategy's VERIFY phase — this is the PLAN-side bookkeeping for the reset already mandated by `AGENTS.md` §2's Multi-Strategy Lifecycle Loop.
4. **Environment Parity & Architecture Isolation Check.** Using the Target SUT Stack recorded in `PERF_SPEC.md`, confirm and record the SUT's concurrency/architecture limits — e.g. single-process Node.js (one event loop, no in-process horizontal scaling), SQLite single-writer (one write transaction committed at a time, concurrent writers serialize or fail with `SQLITE_BUSY`), a JVM service's configured connection pool size, or an in-memory cache that resets on restart. Also confirm the load generator (k6) and the SUT are not competing for the same CPU/RAM/network interface in a way that would contaminate results (e.g. running k6 and the SUT on the same single-core VM makes the load generator itself a bottleneck). These limits are required inputs to `bottleneck-auditor`'s later 4-layer RCA — they must be on record now, not discovered mid-audit. Also read the `[INFO] Host machine: ...` line printed by `hooks/session-start.sh`'s output for this session and record it as the **Host Machine Specification** in `PERF_PLAN.md` — this is captured automatically once per session, never typed from memory or assumed to match a prior engagement's machine.
5. **Task Breakdown & Plan Persistence.** For **every** strategy declared in `PERF_SPEC.md`'s metadata, break down the concrete BUILD/VERIFY/AUDIT tasks (script to build, sanity run, full load run) plus any test-data seeding specific to that strategy. Write (or update) `perf-test/PERF_PLAN.md` with the Target Authorization & Third-Party Sandbox Gate, the Environment Parity Summary, the Clean Baseline Verification Checklist, the Idle Telemetry Table, and the per-strategy Task Breakdown Table. This file is the required input for BUILD (`/perf-script`) — no later phase proceeds without it.

## Common Rationalizations

| Common Agent Rationalization | Engineering Reality |
| --- | --- |
| "The server is already running, no need to restart it." | In-memory caches, connection pools, and event-loop-resident state (timers, unclosed handles) persist across requests but not across restarts — an already-running server is exactly the polluted state Non-Negotiable 2 exists to eliminate. |
| "Re-seeding the DB takes time, let's just reuse the existing data." | Row count and index fragmentation directly affect query planner behavior and I/O — stale data invalidates the baseline. Re-seed before every comparative run, no exceptions. |
| "Let's skip straight to `/perf-script` to save time — planning can happen later." | BUILD needs the architecture limits and per-strategy task breakdown that only PLAN produces; skipping it means BUILD works from undocumented assumptions, which is exactly what Non-Negotiable 4 (Surface Assumptions) forbids. |
| "Idle CPU is at 8%, but that's probably just a background process, close enough to baseline." | An unexplained idle-CPU reading above 5% means the "idle" measurement isn't actually idle — identify and stop the competing process before measuring, or the baseline is contaminated before the first VU even starts. |
| "The load generator and the SUT are on the same laptop, that's fine for now." | If the load generator competes for the same CPU/network as the SUT, measured latency reflects contention on the test rig, not the SUT's real behavior — record and disclose this topology explicitly, or use separate hosts if the numbers must be authoritative. |
| "We already know the architecture limits from a previous project, no need to re-verify." | Every SUT's precise concurrency model (single-writer, connection pool size, process count) must be confirmed for *this* target — assumptions carried over from an unrelated project are exactly the kind of unmeasured claim Non-Negotiable 1 forbids. |
| "The user already told me to test example.com, that's confirmation enough — no need to ask again explicitly." | A casual mention of a URL is not the same as confirming authorization to load-test it, especially once Stress/Spike may escalate to hundreds of concurrent VUs. Ask directly, and wait for an explicit affirmative answer before proceeding. |
| "The checkout flow calls a payment gateway, but it's probably already using test credentials." | "Probably" is exactly the kind of unmeasured assumption Non-Negotiable 1 exists to forbid — applied here to authorization, not just latency. Confirm explicitly with the user which credential mode is active before a full-load run touches that route. |

## Red Flags

- PLAN proceeds despite `perf-test/PERF_SPEC.md` not existing — a plan gets drafted against an unestablished or imagined spec.
- A load run executes with no captured evidence of a preceding server restart and DB re-seed.
- Baseline reset is asserted in prose ("I restarted the server") with no command output attached.
- An idle-CPU reading above 5% is accepted as "close enough" instead of investigated and resolved before proceeding.
- `perf-test/PERF_PLAN.md` is missing, or was not updated to reflect the current engagement's declared strategies.
- A strategy declared in `PERF_SPEC.md` has no corresponding row in the Task Breakdown Table.
- SUT architecture limits (single-writer DB, single-process server, connection pool size, etc.) are not written down anywhere before AUDIT begins.
- The plan file is written outside `perf-test/` — to the project root, or worse, inside `.claude/` — a direct Workspace Boundary Rule violation.
- VERIFY/AUDIT for a second or later declared strategy begins by reusing the baseline reset evidence captured for an earlier strategy, instead of executing and recording a fresh restart/re-seed/idle-check specific to that strategy's run.
- `PERF_PLAN.md`'s Environment Parity Summary is missing Host Machine Specification, or the values don't trace back to this session's `session-start.sh` output.
- PLAN proceeds to Clean Baseline Enforcement or any later step without a captured, explicit user confirmation that the target host is an authorized test/staging environment.
- AUDIT's full-load run touches an in-scope route with a live third-party integration with no captured confirmation that it's sandboxed/mocked.

## Required Output Format

Persist `perf-test/PERF_PLAN.md` in this shape — parity summary, then the baseline checklist with captured evidence, then idle telemetry, then the per-strategy task breakdown:

```markdown
# PERF_PLAN.md

## Target Authorization & Third-Party Sandbox Gate
- Target Host: https://staging.eshop.example.com
- Authorization Confirmed By User: Yes — "Confirmed, this is our staging environment, safe to load test." (captured 2026-07-31T10:02:00Z)
- Heuristic Check: No production-like markers detected (subdomain contains "staging")
- Third-Party Integrations In Scope:
  - Stripe (payment, used by POST /api/checkout) — confirmed running in Test Mode by user
  - Twilio (SMS OTP, used by POST /api/checkout) — confirmed using sandbox credentials by user

## Environment Parity Summary
- Target SUT Stack (from PERF_SPEC.md): Node.js (Express) + SQLite, single-process/single-writer
- Architecture Limits: single event loop; SQLite single-writer (WAL mode: no) — concurrent writes serialize or raise SQLITE_BUSY
- Load Generator / SUT Topology: separate hosts (k6 on host A, SUT on host B, 4 vCPU each)
- Host Machine Specification (captured via hooks/session-start.sh, this engagement's run):
  - CPU: {{CPU_MODEL}}, {{CPU_CORES}} cores
  - RAM: {{TOTAL_RAM_GB}}GB
  - OS: {{OS_INFO}}
  - Captured: {{ISO_8601_TIMESTAMP}}

## Clean Baseline Verification Checklist

| Strategy | Executed Before | Restart Evidence | Re-seed Evidence | Idle Check | Status |
|---|---|---|---|---|:---:|
| Load (baseline) | PLAN | `$ pkill -f "node server.js" && node server.js &` <br>`[server] listening on :3000 (pid 48213)` | `$ node ./scripts/seed-database.js`<br>`Seeded 3 tables: users(50), products(200), orders(0)` | CPU 2.1%, RSS 145MB | PASS |
| Spike | VERIFY/AUDIT (re-applied before spike run) | *(Captured fresh by perf-architect before spike VERIFY starts)* | *(Captured fresh by perf-architect before spike VERIFY starts)* | *(Target CPU < 5%)* | PENDING |

## Idle Telemetry Table

| Metric              | Idle Value | Threshold           | Status |
|----------------------|-----------:|-----------------------|:------:|
| CPU utilization       |       2.1% | < 5%                  | PASS   |
| RSS / RAM              |     145 MB | Stable ±5% over 60s   | PASS   |
| Background cron jobs   |       None | None running          | PASS   |

## Task Breakdown Table (per declared strategy)

| Strategy         | BUILD Task                          | VERIFY Task              | AUDIT Task                              |
|--------------------|---------------------------------------|-----------------------------|--------------------------------------------|
| Load (baseline)    | Build `perf-test/scripts/baseline.k6.js` | 1 VU / 30s sanity run     | Full load run at target RPS; 4-layer RCA if SLO breached |
| Spike              | Build `perf-test/scripts/spike.k6.js`    | 1 VU / 30s sanity run     | Full ramp 50→500 VU; 4-layer RCA if SLO breached |
```

- Every row must carry a one-line evidence excerpt (a real captured command/output line) once its `Status` moves from `PENDING` to `PASS`; a `PASS` with no evidence excerpt is non-compliant.
- Every strategy declared in `PERF_SPEC.md`'s metadata must have its own row in the Clean Baseline Verification Checklist — the first strategy's row is filled in during PLAN; every subsequent strategy's row stays `PENDING` until `perf-architect` executes and records that strategy's fresh reset immediately before its own VERIFY phase.
- Every Idle Telemetry row must show a `Status` of `PASS` or `FAIL` against its threshold — a `FAIL` blocks proceeding to BUILD until resolved and re-measured.
- Every strategy declared in `PERF_SPEC.md`'s metadata must have exactly one row in the Task Breakdown Table.
- Host Machine Specification must be captured from `session-start.sh`'s actual `[INFO]` output for this session — never typed from memory or assumed to match a prior engagement's machine.
- The Target Authorization & Third-Party Sandbox Gate section must appear first in `PERF_PLAN.md`, before Environment Parity Summary — a `PERF_PLAN.md` missing this section, or containing an unconfirmed/placeholder value in it, blocks every subsequent phase regardless of how clean the rest of the plan looks. Unlike every other check in this file, this one cannot be self-approved by the Master from automated output alone — it requires a captured, direct human response in this conversation.
- Prose outside the tables is capped at 3-5 bullet points.
