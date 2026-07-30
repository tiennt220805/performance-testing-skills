# AGENTS.md

Operational instruction manual for AI Agents **executing performance testing tasks** against a target System Under Test (SUT), using this skill suite. If you are instead contributing to or modifying this skill suite itself, read `CLAUDE.md`.

## 1. System Introduction & Workspace Boundaries

At the start of every session that involves performance testing, read `skills/using-performance-testing-skills/SKILL.md` first. It is the meta-skill and operating protocol for this entire suite — it defines the workflow router and the 7 Non-Negotiable Performance Engineering Rules that govern every phase below. Do not invoke any `/perf-*` command before internalizing that skill.

Ground rules for this manual:

- This suite is **100% Grafana k6-centric** (Test-as-Code). Do not fall back to JMeter, GUI test plans, XML, or JVM tuning under any circumstance.
- Command trigger files live at the repository root under `commands/` (e.g. `commands/perf-spec.md`), **not** under `.claude/commands/`. This repo is mounted as a `git submodule` at a target project's `.claude/` directory, so no nested `.claude/` folder exists inside it.
- Output is **metrics-first**: RPS, latency percentiles (p50/p90/p95/p99), Error Rate %, and Error Distribution Signatures take priority over prose. Explanatory text is capped at 3-5 bullet points per section.

### Workspace Boundary Rule

`.claude/` (this submodule) is the **engine** — skill/command/persona/reference definitions only. It is never a workspace for test artifacts.

- **Input Source**: all user-supplied input (HAR captures, `spec.md`, `openapi.json`) MUST be read from the target project's `docs/` directory (or its root if `docs/` doesn't exist) — never assumed, never fabricated, never read from inside `.claude/`.
- **Output Artifacts**: every artifact an agent generates MUST be written under the target project's `perf-test/` directory. Agents must NOT read or write any artifacts directly inside `.claude/` under any circumstance — not scripts, not logs, not reports, not scratch files.
- If `docs/` is missing or empty when DEFINE (`/perf-spec`) is invoked, stop and ask the user for the input artifacts rather than inventing a spec from assumptions.
- If `perf-test/` does not yet exist, create it (and its subdirectories `scripts/`, `logs/`, `reports/`) as part of the first artifact-producing step — do not wait for the user to scaffold it.

### Environment Hook Check

Before executing **any** `/perf-*` command, the agent MUST confirm that `hooks/session-start.sh` has already run successfully for this session.

- If the hook has not run yet, run it first — do not proceed on the assumption that the environment is fine.
- If the hook reports a missing `k6` binary or a `k6` version mismatch, **STOP IMMEDIATELY** and surface the exact error to the user. Do not attempt to work around a missing/wrong `k6` install, and do not proceed with any lifecycle phase until the user has fixed the environment and the hook passes.

## 2. Workflow Lifecycle (The 6-Step Gatekeeping Lifecycle)

Every performance engagement moves through six sequential, gated phases, run under a **Master-SubAgent Adversarial Pattern**: the `perf-architect` persona acts as the **Master Agent** (execution — scripts, test runs, draft reports), and the `bottleneck-auditor` persona is spawned as an **independent Sub-Agent** during VERIFY, AUDIT, and SHIP to adversarially challenge the Master's findings before anything is reported to the user. Do not skip a phase, run them out of order, or skip a required Sub-Agent audit — each phase's (audited) output is required input for the next.

```text
DEFINE          PLAN            BUILD             VERIFY                AUDIT                  SHIP
/perf-spec  ➔  /perf-plan  ➔  /perf-script  ➔  /perf-verify     ➔   /perf-audit      ➔     /perf-gate
SLOs &          Env baseline    k6 script         1 VU sanity           Full load test         Scorecard &
workload        checklist &     (HAR/OpenAPI/     + Sub-Agent           + Sub-Agent RCA         + Sub-Agent
model           task plan       codebase +        audit gate            audit (4-layer          Gate Audit
                                correlation)                             generalized stack)      sign-off
```
*Note: If `PERF_SPEC.md` declares multiple strategies, VERIFY and AUDIT loop sequentially per strategy with a clean baseline reset between runs.*

| Step | Command | Reads From | Writes To | Sub-Agent Gate |
|---|---|---|---|---|
| DEFINE | `/perf-spec` | `docs/` (`.har`, `spec.md`, `openapi.json`) | `perf-test/PERF_SPEC.md` | No |
| PLAN | `/perf-plan` | `perf-test/PERF_SPEC.md` + live SUT environment | `perf-test/PERF_PLAN.md` | No |
| BUILD | `/perf-script` | `perf-test/PERF_SPEC.md`, `perf-test/PERF_PLAN.md`, `docs/` source artifacts | `perf-test/scripts/*.k6.js` | No |
| VERIFY | `/perf-verify` | `perf-test/scripts/*.k6.js` | `perf-test/logs/{strategy}-verify.log`, `perf-test/reports/verify-sanity-{strategy}.md` | **Yes** |
| AUDIT | `/perf-audit` | `perf-test/scripts/*.k6.js`, `perf-test/PERF_SPEC.md` | `perf-test/logs/{strategy}-audit.log`, `perf-test/reports/audit-rca-{strategy}.md` | **Yes** |
| SHIP | `/perf-gate` | ALL `perf-test/reports/audit-rca-*.md`, `perf-test/PERF_SPEC.md` | `perf-test/reports/final-gate-scorecard.md` | **Yes** |

- **DEFINE** (`/perf-spec`) — Master reads `docs/` (HAR capture, `spec.md`, and/or `openapi.json`) and establishes the SUT profile, target SLOs per endpoint (RPS, max fail rate %, p50/p95/p99), and the selected test strategy (**Load / Stress / Spike / Soak**). Persists all of this to `perf-test/PERF_SPEC.md`. No test design begins without this file existing.
- **PLAN** (`/perf-plan`) — Master verifies environment parity and enforces a clean baseline (server restart, DB re-seed). Persists the verification checklist and task breakdown to `perf-test/PERF_PLAN.md`.
- **BUILD** (`/perf-script`) — Master engineers the k6 JavaScript script using the **Primary Parsers** (`parse-har`, `parse-openapi`) against whatever source artifact is available in `docs/`; if neither a HAR capture nor an OpenAPI document is available, falls back to `parse-codebase` (static route/handler discovery directly from the SUT's source). Applies the `correlation.md` module to handle dynamic token extraction and session chaining (login-once-per-VU, bearer token propagation, multi-step flow correlation). Parameterizes data with `SharedArray`. Writes the finished script(s) to `perf-test/scripts/*.k6.js`.
- **VERIFY** (`/perf-verify`) — Master runs a 1 VU Sanity check (30s) against the script, saves the raw unedited CLI output to `perf-test/logs/{strategy}-verify.log` (e.g. `baseline-verify.log`), and drafts a checks-vs-thresholds summary ➔ **Sub-Agent spawned (Audit Gate 1)** to audit the Master's logic against the raw log and declared thresholds. The audited result is written to `perf-test/reports/verify-sanity-{strategy}.md`, where `{strategy}` is the name of the strategy/script under test (e.g. `verify-sanity-baseline.md`).
- **AUDIT** (`/perf-audit`) — Master runs the full load profile, saves raw output to `perf-test/logs/{strategy}-audit.log` (e.g. `baseline-audit.log`, `spike-audit.log`), and drafts a telemetry/bottleneck report ➔ **Sub-Agent spawned** for Adversarial Root Cause Analysis across the **4-Layer Generalized Architecture Stack** (Layer 1 Transport → Layer 4 Infrastructure; see §4). The audited result is written to `perf-test/reports/audit-rca-{strategy}.md` (e.g. `audit-rca-baseline.md`, `audit-rca-spike.md`) — never fixed filenames (`*.log` wildcards or a bare `audit-rca.md`), which would be overwritten by the next strategy in the loop.
- **SHIP** (`/perf-gate`) — Master reads **every** file matching `perf-test/reports/audit-rca-*.md` (one per audited strategy) plus `perf-test/PERF_SPEC.md`, and drafts the executive scorecard aggregating all of them ➔ **Sub-Agent spawned** to perform the final Gate Audit and sign off the binary verdict: `FINAL GATE DECISION: PASS / REJECT`. Written to `perf-test/reports/final-gate-scorecard.md`, plus CI/CD integration guidance.

An agent must not jump from DEFINE straight to AUDIT, or re-run SHIP without a preceding AUDIT in the same engagement — each phase's evidence is the input contract for the next. No draft produced by the Master during VERIFY, AUDIT, or SHIP may reach the user without first passing the Sub-Agent audit described in §4.

### Multi-Strategy Lifecycle Loop

`perf-test/PERF_SPEC.md` may declare more than one test strategy for the same engagement (e.g. a Load Test baseline at 50 VU **and** a Spike Test ramping 50 → 500 VU). When it does:

- **BUILD** (`/perf-script`) may generate multiple k6 scripts in the same pass, one per declared strategy (e.g. `perf-test/scripts/baseline.k6.js`, `perf-test/scripts/spike.k6.js`).
- **VERIFY** (`/perf-verify`) and **AUDIT** (`/perf-audit`) MUST loop each strategy/script **separately and sequentially** — run the 1 VU sanity check and the full load audit for `baseline.k6.js` to completion (including its own Sub-Agent gate) before starting the same cycle for `spike.k6.js`. Never interleave raw log capture across strategies.
- Before VERIFY/AUDIT begins for each subsequent strategy in the loop, the environment MUST be reset per the PLAN phase's clean-baseline checklist (server restart + DB re-seed) — re-run this reset even though `/perf-plan` itself is not re-invoked. Running `spike.k6.js` against state left over from `baseline.k6.js`'s run invalidates both results (Non-Negotiable 2, "Enforce Clean Baseline").
- Every artifact produced per strategy — raw logs and reports alike — MUST be named with its own explicit strategy suffix: `perf-test/logs/{strategy}-verify.log`, `perf-test/logs/{strategy}-audit.log`, `perf-test/reports/verify-sanity-{strategy}.md`, `perf-test/reports/audit-rca-{strategy}.md`. Never a generic wildcard-style name (e.g. a bare `verify.log`) or a fixed filename shared across strategies — writing `baseline` and `spike` results to the same path would silently overwrite the earlier strategy's physical evidence.
- **SHIP** (`/perf-gate`) may only assemble the executive scorecard once **every** declared strategy has completed AUDIT with an `APPROVED` verdict and meets its SLOs. It aggregates by reading all files matching `perf-test/reports/audit-rca-*.md`. If any one strategy is still pending, failed, or not yet audited, SHIP cannot run — surface which strategy is blocking instead of shipping a partial scorecard.

## 3. Skill & Command Routing Matrix

| User Intent | Slash Command | Target Skill | Input Flexibility / RCA Scope | Selective Sub-Skills (JIT Loaded) |
|---|---|---|---|---|
| Define SLOs & workload model from `docs/` input | `commands/perf-spec.md` | `skills/perf-requirements-and-slo/SKILL.md` | Accepts `.har`, `spec.md`, and/or `openapi.json` from `docs/` | — |
| Plan tasks & reset baseline | `commands/perf-plan.md` | `skills/test-environment-and-baseline/SKILL.md` | Verifies SUT architecture limits regardless of stack | — |
| Build k6 script with dynamic correlation | `commands/perf-script.md` | `skills/script-engineering-and-correlation/SKILL.md` | Primary: `parse-har` / `parse-openapi`. Fallback: `parse-codebase`. Applies `correlation.md` (token/session chaining) | 1 Ingestion (`parse-har.md` OR `parse-openapi.md` OR `parse-codebase.md`) + `correlation.md` (mandatory) + 1 Strategy file per declared strategy in `PERF_SPEC.md` (e.g. both `profile-load-test.md` AND `profile-spike-test.md` if both are declared) — never load a strategy file for an undeclared strategy + 1 Protocol (`protocol-http.md`) |
| Dry-run 1 VU verification | `commands/perf-verify.md` | `skills/smoke-and-sanity-validation/SKILL.md` | Sanity gate (Audit Gate 1) before any full load run | — |
| Full load test & generalized 4-layer RCA | `commands/perf-audit.md` | `skills/bottleneck-root-cause-analysis/SKILL.md` | Layer 1 Transport → Layer 4 Infrastructure, stack-agnostic | Layers matching the SUT stack declared in `PERF_SPEC.md` (`rca-layer1-transport.md` → `rca-layer4-infrastructure.md`) + 1 Audit Matrix matching the test type (`rca-spike.md` OR `rca-load-stress.md` OR ...) |
| Quality gate scorecard & CI/CD | `commands/perf-gate.md` | `skills/slo-reporting-and-insights/SKILL.md` | Aggregates ALL `perf-test/reports/audit-rca-*.md`; final Sub-Agent sign-off, binary PASS/REJECT | — |

If a user request does not clearly map to a row above, re-read `skills/using-performance-testing-skills/SKILL.md` to resolve ambiguity before guessing at a skill.

### Just-In-Time (JIT) Context Loading Protocol

Skill-local reference material lives under each skill's own `skills/<skill-name>/references/` subdirectory (`CLAUDE.md` §3, Context Window Discipline) and is not meant to be loaded all at once.

- **Rule**: never load every file in a skill's `references/` directory at once — open only what the current engagement's configuration requires.
- **Protocol**: (1) read `perf-test/PERF_SPEC.md` for its metadata (Target SUT Stack, Test Strategy, Ingestion Source); (2) match that metadata to the exact filenames listed in the **Selective Sub-Skills (JIT Loaded)** column of the Routing Matrix above — that column is authoritative for which files to open per command; (3) leave every non-matching reference file unread, even "just in case."

## 4. Persona Activation & Sub-Agent Protocol

Two personas are available under `agents/`, operating in a **Master-SubAgent Adversarial Pattern** rather than simple sequential role-switching:

- **`agents/perf-architect.md`** — the **Master Agent**. Active during DEFINE, PLAN, and BUILD (`/perf-spec`, `/perf-plan`, `/perf-script`), and remains the executing agent throughout VERIFY, AUDIT, and SHIP (running commands, generating scripts, drafting reports/telemetry). The Master never grades its own work for the final report.
- **`agents/bottleneck-auditor.md`** — the **Sub-Agent**, spawned as an independent process during VERIFY, AUDIT, and SHIP (`/perf-verify`, `/perf-audit`, `/perf-gate`). It does not execute tests; it inspects what the Master already produced. It acts as an **Independent Skeptical Auditor**: it inspects raw CLI telemetry from the relevant `perf-test/logs/{strategy}-{phase}.log` file(s), challenges the Master's findings, enforces non-sycophantic evaluation against `perf-test/PERF_SPEC.md` SLOs, and blocks premature or inaccurate `PASS` verdicts.

### The 4-Layer Generalized Architecture Stack (used during AUDIT)

Root-cause analysis is not tied to one specific tech stack — it walks four generalized layers, from the load-generator boundary down to the hardware, so the same audit model applies whether the SUT is Node.js/SQLite, a JVM service with Postgres, or anything else:

| Layer | Scope | Example Signals |
|---|---|---|
| **Layer 1 — Transport** | Client/load-generator boundary and network transport | k6 VU/connection-pool exhaustion, TLS/handshake failures, DNS resolution errors, load-generator-side false positives |
| **Layer 2 — Application** | SUT process/runtime execution | Event-loop lag or thread-pool saturation, CPU-bound handlers, unbounded in-memory caches/session stores, token/credential handling bugs |
| **Layer 3 — Data** | Persistence layer | Write-lock/row-lock contention (e.g. `SQLITE_BUSY`), connection pool exhaustion, slow queries, replication lag |
| **Layer 4 — Infrastructure** | OS and hardware | CPU/RSS ceilings, disk I/O saturation vs. OS page cache, network interface saturation |

The Sub-Agent must check all four layers before attributing a bottleneck to any single one — see `agents/bottleneck-auditor.md` for the full audit procedure and stack-specific examples.

### Spawn Trigger

The Master spawns the `bottleneck-auditor` Sub-Agent immediately after drafting (and before reporting) results for any of: 1 VU sanity run (`/perf-verify`), full load test telemetry (`/perf-audit`), or the executive scorecard (`/perf-gate`).

### Sub-Agent Isolation

`bottleneck-auditor` MUST be spawned in an independent process/context — a clean context window (e.g. via the Task tool) — never as a continuation of the Master's own reasoning turn. This is what makes the audit adversarial rather than self-review wearing a different label.

The payload handed to the Sub-Agent contains **exactly three clean components** and nothing else:
1. Target SLOs from `perf-test/PERF_SPEC.md`.
2. Input Evidence Component — the shape of this component differs by gate: for Gate 1 (`/perf-verify`) and Gate 2 (`/perf-audit`), it is the raw, unedited execution log for the run under audit (`perf-test/logs/{strategy}-{phase}.log`); for Gate 3 (`/perf-gate`), it is ALL already-`APPROVED` strategy reports (`perf-test/reports/audit-rca-*.md`) for every strategy declared in `PERF_SPEC.md`. Gate 3 audits aggregate scorecard completeness and consistency across the declared strategies — it does not re-run raw-log RCA, since that root-cause work was already performed and approved at Gate 2.
3. Master's Draft Report (the summary/report the Master intends to present).

The Master's own chain-of-thought / reasoning history that produced the draft MUST NOT be passed into the Sub-Agent's context. The Sub-Agent audits the *artifacts*, not the Master's internal reasoning — passing along the reasoning trail would let the Master's framing bias the "independent" verdict.

### Output Payload from Sub-Agent

Per the `[AUDIT_FEEDBACK_BLOCK]` format defined in `agents/bottleneck-auditor.md`:
- `AUDIT_VERDICT`: `APPROVED` or `REJECTED`.
- List of Bypassed Errors — for Gate 1/Gate 2, any error signature present in the reviewed `perf-test/logs/{strategy}-{phase}.log` file but omitted or downplayed in the Master's draft; for Gate 3, any SLO breach, missing strategy, or contradiction present in one of the `perf-test/reports/audit-rca-*.md` files but smoothed over, averaged away, or omitted from the Master's aggregate scorecard draft.
- Required Corrections — precise instructions for what the Master must fix before re-submitting.

The Sub-Agent's final, audited output is what gets persisted to the phase's report file (`perf-test/reports/verify-sanity-{strategy}.md`, `perf-test/reports/audit-rca-{strategy}.md`, or `perf-test/reports/final-gate-scorecard.md`) — a report file must never be written from an un-audited Master draft.

### Resolution Rule

If `AUDIT_VERDICT: REJECTED`, the Master must apply the Required Corrections and resubmit a revised draft for another Sub-Agent pass — it may not present the original draft to the user, may not write the un-audited draft to the `perf-test/reports/` file, and may not overrule a `REJECTED` verdict unilaterally. Only an `APPROVED` verdict permits the Master to output the final user-facing response for that phase and persist the report. If a fix requires re-entering BUILD (e.g. a script defect found during audit forces a rewrite), treat it as a new pass through the lifecycle starting at BUILD, not a shortcut around the Sub-Agent gate.

**Retry Limit / Exit Condition**: if the Sub-Agent returns `AUDIT_VERDICT: REJECTED` **3 consecutive times** for the same phase and the same script/strategy, the Master MUST stop the self-correction loop for that script/strategy — do not attempt a 4th silent revision. Preserve all rejected drafts and raw logs as-is, and escalate directly to the user with a summary of all 3 rejections (verdicts, contradictions, required actions) for a human decision on how to proceed. This counter is scoped per script/strategy: 2 consecutive rejections on `baseline.k6.js` followed by a rejection on `spike.k6.js` is 1 rejection against the `spike` counter, not a 3rd against `baseline` — each strategy's retry count is tracked and reset independently in the Multi-Strategy Lifecycle Loop (§2). For SHIP (`/perf-gate`), which operates across all strategies at once, the 3-consecutive-rejection counter is scoped to the SHIP phase as a whole for the current engagement, rather than per strategy.

## 5. Execution Gatekeeping & Proof Protocol

No phase may be marked complete without quantitative, runtime-generated evidence. This is the same standard defined by the 7 Non-Negotiables in `skills/using-performance-testing-skills/SKILL.md` — restated here as hard exit criteria:

- A phase is **not complete** if its claim is supported only by prose. Every completion must attach a Markdown table and/or a fenced ASCII log block containing real numbers from this session's execution, backed by a raw log file physically present under `perf-test/logs/{strategy}-{phase}.log`.
- `/perf-verify` completion requires 1 VU execution evidence with checks and thresholds shown as separate result sets, a persisted `perf-test/logs/{strategy}-verify.log`, and a persisted `perf-test/reports/verify-sanity-{strategy}.md` for the strategy under test.
- `/perf-audit` completion requires a baseline-vs-actual telemetry table and an error distribution signature demonstrating that all 4 layers were inspected, even if the bottleneck is isolated to a single layer — do not report a bottleneck without the runtime data that proves it (Non-Negotiable 3, "Measure Before Optimizing") — a persisted `perf-test/logs/{strategy}-audit.log`, and a persisted `perf-test/reports/audit-rca-{strategy}.md` for the strategy under test. When multiple strategies are declared, every one of them requires its own persisted, `APPROVED` `audit-rca-{strategy}.md` (and matching `{strategy}-audit.log`) before SHIP may run.
- `/perf-gate` completion requires an explicit terminal verdict line: `FINAL GATE DECISION: PASS` or `FINAL GATE DECISION: REJECT`, and a persisted `perf-test/reports/final-gate-scorecard.md` that accounts for every file matched by `perf-test/reports/audit-rca-*.md`. An ambiguous or omitted verdict, or a scorecard that ignores one of the matched strategy reports, is treated as a failed gate.
- No artifact required by this section may ever be written inside `.claude/` — if an agent finds itself about to write a log, script, or report into `.claude/`, that is a Workspace Boundary Rule violation (§1) and must be corrected before proceeding.
- If asked to skip a gate ("just assume it passes", "we don't have time to verify"), refuse and state which of the 7 Non-Negotiables the shortcut would violate, per `CLAUDE.md` §2 and the reciprocal rules in `skills/using-performance-testing-skills/SKILL.md`.
