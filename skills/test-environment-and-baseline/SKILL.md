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
2. **Clean Baseline Enforcement (Non-Negotiable 2).** Every comparative run requires, immediately before execution:
   - A full server process restart (kill and relaunch the SUT process — never rely on a hot reload or a long-running process retaining prior in-memory state).
   - A database re-seed to a known, deterministic state (clear polluted tables or rebuild the database file from a fixture/schema script).
   - An **Idle Baseline measurement** captured right after restart and before any load: CPU utilization **< 5%**, RSS/RAM holding steady (not still climbing from a cold-start allocation spike), and no competing background cron jobs or scheduled tasks running on the SUT host.
   - Do not proceed to `/perf-script` or a load run until all three steps above have been executed and their output captured as evidence — a restart/re-seed/idle-check that is merely claimed, without a captured log line proving it ran, does not satisfy this rule.
   - **This checklist is a reusable procedure, not a one-off static record.** While `/perf-plan` itself is invoked only once, every subsequent strategy declared in `PERF_SPEC.md` requires a fresh, independent baseline reset before its VERIFY/AUDIT pass begins. The `perf-architect` Master Agent MUST execute a fresh server restart + DB re-seed + idle check, and append/update the fresh execution evidence into `PERF_PLAN.md`'s strategy-aware checklist table (see Required Output Format) before initiating that strategy's VERIFY phase — this is the PLAN-side bookkeeping for the reset already mandated by `AGENTS.md` §2's Multi-Strategy Lifecycle Loop.
3. **Environment Parity & Architecture Isolation Check.** Using the Target SUT Stack recorded in `PERF_SPEC.md`, confirm and record the SUT's concurrency/architecture limits — e.g. single-process Node.js (one event loop, no in-process horizontal scaling), SQLite single-writer (one write transaction committed at a time, concurrent writers serialize or fail with `SQLITE_BUSY`), a JVM service's configured connection pool size, or an in-memory cache that resets on restart. Also confirm the load generator (k6) and the SUT are not competing for the same CPU/RAM/network interface in a way that would contaminate results (e.g. running k6 and the SUT on the same single-core VM makes the load generator itself a bottleneck). These limits are required inputs to `bottleneck-auditor`'s later 4-layer RCA — they must be on record now, not discovered mid-audit.
4. **Task Breakdown & Plan Persistence.** For **every** strategy declared in `PERF_SPEC.md`'s metadata, break down the concrete BUILD/VERIFY/AUDIT tasks (script to build, sanity run, full load run) plus any test-data seeding specific to that strategy. Write (or update) `perf-test/PERF_PLAN.md` with the Environment Parity Summary, the Clean Baseline Verification Checklist, the Idle Telemetry Table, and the per-strategy Task Breakdown Table. This file is the required input for BUILD (`/perf-script`) — no later phase proceeds without it.

## Common Rationalizations

| Common Agent Rationalization | Engineering Reality |
| --- | --- |
| "The server is already running, no need to restart it." | In-memory caches, connection pools, and event-loop-resident state (timers, unclosed handles) persist across requests but not across restarts — an already-running server is exactly the polluted state Non-Negotiable 2 exists to eliminate. |
| "Re-seeding the DB takes time, let's just reuse the existing data." | Row count and index fragmentation directly affect query planner behavior and I/O — stale data invalidates the baseline. Re-seed before every comparative run, no exceptions. |
| "Let's skip straight to `/perf-script` to save time — planning can happen later." | BUILD needs the architecture limits and per-strategy task breakdown that only PLAN produces; skipping it means BUILD works from undocumented assumptions, which is exactly what Non-Negotiable 4 (Surface Assumptions) forbids. |
| "Idle CPU is at 8%, but that's probably just a background process, close enough to baseline." | An unexplained idle-CPU reading above 5% means the "idle" measurement isn't actually idle — identify and stop the competing process before measuring, or the baseline is contaminated before the first VU even starts. |
| "The load generator and the SUT are on the same laptop, that's fine for now." | If the load generator competes for the same CPU/network as the SUT, measured latency reflects contention on the test rig, not the SUT's real behavior — record and disclose this topology explicitly, or use separate hosts if the numbers must be authoritative. |
| "We already know the architecture limits from a previous project, no need to re-verify." | Every SUT's precise concurrency model (single-writer, connection pool size, process count) must be confirmed for *this* target — assumptions carried over from an unrelated project are exactly the kind of unmeasured claim Non-Negotiable 1 forbids. |

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

## Required Output Format

Persist `perf-test/PERF_PLAN.md` in this shape — parity summary, then the baseline checklist with captured evidence, then idle telemetry, then the per-strategy task breakdown:

```markdown
# PERF_PLAN.md

## Environment Parity Summary
- Target SUT Stack (from PERF_SPEC.md): Node.js (Express) + SQLite, single-process/single-writer
- Architecture Limits: single event loop; SQLite single-writer (WAL mode: no) — concurrent writes serialize or raise SQLITE_BUSY
- Load Generator / SUT Topology: separate hosts (k6 on host A, SUT on host B, 4 vCPU each)

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
- Prose outside the tables is capped at 3-5 bullet points.
