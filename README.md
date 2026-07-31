# performance-testing-skills

**A safety-first, evidence-first Claude Skills suite for Grafana k6 performance engineering.**

<!-- TODO: replace PLACEHOLDER_BANNER_IMAGE_URL with the real image link -->

![performance-testing-skills banner](https://lh3.googleusercontent.com/d/1-83NwFlC0RNfYSBBGP_d4ClR2tXHT1Bk)

```text
  DEFINE          PLAN            BUILD             VERIFY                AUDIT                  SHIP
 ┌──────┐      ┌──────┐      ┌───────────┐      ┌───────────┐      ┌───────────┐      ┌───────────┐
 │ SLOs │ ───▶ │ Env  │ ───▶ │ k6 Script │ ───▶ │ 1 VU      │ ───▶ │ Full Load │ ───▶ │ Scorecard │
 │Model │      │Reset │      │  + Corr.  │      │ Sanity    │      │ + 4L RCA  │      │ + Gate    │
 └──────┘      └──────┘      └───────────┘      └───────────┘      └───────────┘      └───────────┘
 /perf-spec     /perf-plan     /perf-script       /perf-verify        /perf-audit         /perf-gate
```

---

## Table of Contents

- [Overview](#overview)
- [Key Differentiators](#key-differentiators)
- [Commands](#commands)
- [Installation](#installation)
- [Usage](#usage)
- [Skills](#skills)
- [Agent Personas](#agent-personas)
- [How Skills Work](#how-skills-work)
- [Project Structure](#project-structure)
- [Reference Checklists](#reference-checklists)
- [Prerequisites](#prerequisites)
- [Why This Suite Exists](#why-this-suite-exists)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

`performance-testing-skills` is a modular, **100% Grafana k6-centric** performance engineering skill suite for Claude Code. It runs every engagement through a **Master-SubAgent Adversarial Pattern** — a `perf-architect` Master Agent executes the work, and an independent `bottleneck-auditor` Sub-Agent challenges every draft before it ships. The suite is mounted into any target codebase via `git submodule` at that project's `.claude/` directory, reading input artifacts from the target project's `docs/` and writing every generated script, log, and report to `perf-test/` — never into the submodule itself. It is stack-agnostic: the workflow, gates, and RCA model apply equally whether the target is a Node.js/SQLite service, a JVM/Postgres backend, or anything else.

## Key Differentiators

- **Independent Sub-Agent Adversarial Audit** — VERIFY, AUDIT, and SHIP each require a fresh, isolated audit pass before a report can be shown to the user. The Master never grades its own work.
- **Target Authorization & Third-Party Sandbox Gate** — before any full-load run, a human must explicitly confirm the target host is an authorized test/staging environment (never production, never someone else's domain) with in-scope third-party integrations sandboxed — closing off the path from "load test" to accidental denial-of-service.
- **4-Layer Generalized RCA Stack** — bottleneck diagnosis walks Transport → Application → Data → Infrastructure every time, so a single loud signal (e.g. CPU at 100%) never gets blamed as the root cause without checking the other three layers.
- **Multi-Strategy Lifecycle Loop** — Load, Stress, Spike, and Soak strategies run sequentially, each with its own clean-baseline reset and its own dynamically-named evidence files, so one strategy's results can never silently overwrite another's.
- **Optional Observability Stack (Prometheus + Grafana)** — the agent only ever generates config files (`docker-compose.yml`, `prometheus.yml`, provisioning). It never runs `docker compose up` itself; starting containers stays a manual, human action.

## Commands

| Phase  | Command        | What it does                                                      | Key Principle                                                                 |
| ------ | -------------- | ----------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| DEFINE | `/perf-spec`   | Parses `docs/` (HAR, spec, OpenAPI) into SLOs and a test strategy | SLOs come from real input artifacts, never assumed                            |
| PLAN   | `/perf-plan`   | Verifies environment parity and resets to a clean baseline        | Enforce a clean, authorized baseline before any test runs                     |
| BUILD  | `/perf-script` | Engineers the k6 script(s) with dynamic token/session correlation | Scripts mirror real traffic, including auth flows — not guesses               |
| VERIFY | `/perf-verify` | Runs a 1 VU / 30s sanity check, audited at Gate 1                 | Never scale up a script that hasn't first run clean                           |
| AUDIT  | `/perf-audit`  | Runs the full load profile, audited at Gate 2 (4-layer RCA)       | Measure before optimizing — root cause from runtime data, not code inspection |
| SHIP   | `/perf-gate`   | Aggregates every strategy's audited results into a scorecard      | No self-graded pass — an independent Sub-Agent sign-off is mandatory          |

## Installation

This suite is not a plugin-marketplace install — it is mounted as a `git submodule` at your target project's `.claude/` directory:

```bash
git submodule add https://github.com/tiennt220805/performance-testing-skills.git .claude
git submodule update --init --recursive
```

After mounting, confirm the environment hook passes before running any `/perf-*` command:

```bash
bash .claude/hooks/session-start.sh
```

A `[SUCCESS] Session environment validated. Grafana k6 engine ready (version ...)` line means you're ready. A `[FATAL]` line means k6 is missing or below the minimum supported version — fix that first; this suite never proceeds on an unverified environment.

## Usage

> The examples below use an illustrative "EShop" scenario (search/cart/checkout), per `CLAUDE.md` §3's convention — substitute your target project's actual routes and entities.

```
/perf-spec
Define SLOs for the EShop checkout flow from docs/checkout-session.har —
target p95 under 500ms and error rate under 1% at expected launch traffic.
```

```
/perf-plan
Verify the staging environment is ready for the checkout load test and
enforce a clean baseline before we build the script.
```

```
/perf-script
Build a k6 script for the EShop search → cart → checkout flow, correlating
the bearer token issued at login across every subsequent request.
```

```
/perf-verify
Run the 1 VU sanity check on the checkout script before we attempt full load.
```

```
/perf-audit
Run the full load profile against the checkout flow and diagnose any
bottleneck across the transport, application, data, and infrastructure layers.
```

```
/perf-gate
All declared strategies for the checkout flow are audited — assemble the
final scorecard and gate decision.
```

## Skills

| Skill                                                                                    | Phase  | Description                                                                                                                                                                                                    |
| ---------------------------------------------------------------------------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [perf-requirements-and-slo](skills/perf-requirements-and-slo/SKILL.md)                   | DEFINE | Use when defining target SLOs, parsing `docs/` artifacts (`.har`, `spec.md`, `openapi.json`), establishing endpoint workload models, or writing `perf-test/PERF_SPEC.md`.                                      |
| [test-environment-and-baseline](skills/test-environment-and-baseline/SKILL.md)           | PLAN   | Use when planning performance tasks, verifying environment parity, enforcing clean baseline resets (server restart + DB re-seed), or writing `perf-test/PERF_PLAN.md`.                                         |
| [script-engineering-and-correlation](skills/script-engineering-and-correlation/SKILL.md) | BUILD  | Use when engineering Grafana k6 scripts, extracting dynamic tokens/correlation, parameterizing test data via `SharedArray`, or persisting k6 JS files to `perf-test/scripts/`.                                 |
| [smoke-and-sanity-validation](skills/smoke-and-sanity-validation/SKILL.md)               | VERIFY | Use when executing 1 VU sanity dry-runs (30s), validating script correctness before full load, running Sub-Agent Audit Gate 1, or writing `perf-test/reports/verify-sanity-{strategy}.md`.                     |
| [bottleneck-root-cause-analysis](skills/bottleneck-root-cause-analysis/SKILL.md)         | AUDIT  | Use when executing full-load performance tests, conducting 4-layer generalized architecture stack root-cause analysis, running Sub-Agent Audit Gate 2, or writing `perf-test/reports/audit-rca-{strategy}.md`. |
| [slo-reporting-and-insights](skills/slo-reporting-and-insights/SKILL.md)                 | SHIP   | Use when synthesizing multi-strategy executive scorecards, validating overall SLO compliance, running Sub-Agent Audit Gate 3 (Final Sign-off), or writing `perf-test/reports/final-gate-scorecard.md`.         |

The meta-skill [using-performance-testing-skills](skills/using-performance-testing-skills/SKILL.md) is the Constitution and Router — read at the start of every session, before any `/perf-*` command.

## Agent Personas

Two personas operate in an **adversarial** relationship, not a simple hand-off:

| Persona                                            | Role                                                                                                                                                                                                   | Relationship                                                               |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------- |
| [perf-architect](agents/perf-architect.md)         | Master Agent — Lead Performance Engineer. Owns every phase DEFINE → SHIP: negotiates SLOs, enforces baseline discipline, engineers scripts, runs every k6 test, drafts every report.                   | Never the final judge of its own work.                                     |
| [bottleneck-auditor](agents/bottleneck-auditor.md) | Sub-Agent — Independent Skeptical Auditor. Spawned in an isolated context during VERIFY, AUDIT, and SHIP. Never runs k6, never writes scripts — inspects only the raw evidence and the Master's draft. | Renders a binary `APPROVED`/`REJECTED` verdict the Master cannot overrule. |

A `REJECTED` verdict is a hard stop: the Master must revise and resubmit for a fresh audit pass, never present or persist the un-audited draft.

## How Skills Work

Every `SKILL.md` follows the same 7-section anatomy:

```text
┌─────────────────────────────────────────────────────┐
│  SKILL.md                                           │
│                                                     │
│  ┌─ Frontmatter ────────────────────────────────┐   │
│  │ name: <matches directory name>               │   │
│  │ description: "Use when..." (trigger only)    │   │
│  └──────────────────────────────────────────────┘   │
│  Overview                  → 1-2 sentences, no fluff│
│  When to Use               → Concrete triggers      │
│  Core Process / Workflow   → Numbered steps         │
│  Common Rationalizations   → Excuse vs. reality     │
│  Red Flags                 → Observable violations  │
│  Required Output Format    → Enforced output shape  │
└─────────────────────────────────────────────────────┘
```

- **Metrics-first, always.** Prose is capped at 3-5 bullets per section; quantitative results are Markdown tables or fenced ASCII `k6 summary` blocks — never paraphrased numbers.
- **Anti-rationalization by design.** Every skill documents the excuses an agent might use to skip rigor, paired with the engineering reality that rebuts it.
- **JIT reference loading.** Long templates and lookup matrices live in each skill's own `references/` subdirectory and are opened only when the current engagement's configuration calls for them — never all at once.
- **Every gate ends in a verdict.** No `/perf-verify`, `/perf-audit`, or `/perf-gate` output leaves the outcome implicit.

## Project Structure

```text
performance-testing-skills/
├── AGENTS.md                                # Operating manual for AI agents running tests against a target SUT
├── CLAUDE.md                                # Contributor guide for this suite itself
├── commands/                                # 6 thin slash-command triggers
│   ├── perf-spec.md
│   ├── perf-plan.md
│   ├── perf-script.md
│   ├── perf-verify.md
│   ├── perf-audit.md
│   └── perf-gate.md
├── agents/                                  # 2 personas — Master vs. Sub-Agent
│   ├── perf-architect.md
│   └── bottleneck-auditor.md
├── skills/
│   ├── using-performance-testing-skills/    # Constitution & Router (meta-skill)
│   ├── perf-requirements-and-slo/           # DEFINE
│   ├── test-environment-and-baseline/       # PLAN
│   ├── script-engineering-and-correlation/  # BUILD
│   │   └── references/                      #   correlation, parsers, load-profile templates
│   ├── smoke-and-sanity-validation/         # VERIFY
│   ├── bottleneck-root-cause-analysis/      # AUDIT
│   │   └── references/                      #   4-layer RCA + per-strategy audit matrices
│   └── slo-reporting-and-insights/          # SHIP
├── references/                              # 4 top-level, suite-wide reference files (see below)
├── hooks/                                   # session-start.sh + behavioral (non-native) hook manifest
└── .gitignore
```

## Reference Checklists

| Reference                                                                       | Covers                                                                                                                                                                                             |
| ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [slo-cheatsheet.md](references/slo-cheatsheet.md)                               | Industry-benchmark SLO defaults and metric vocabulary (RPS/p50/p90/p95/p99) with provenance rules — never a substitute for stakeholder-defined numbers when `PERF_SPEC.md` states them explicitly. |
| [queueing-theory-mmc.md](references/queueing-theory-mmc.md)                     | M/M/c queueing theory (Little's Law, executor selection) as an estimation tool for planning a starting VU count — explicitly never a substitute for a real k6-measured result.                     |
| [database-concurrency-patterns.md](references/database-concurrency-patterns.md) | SQLite single-writer/WAL semantics, connection-pool sizing formulas, and lock-contention diagnostics (`SQLITE_BUSY`/`SQLITE_LOCKED`) used during Layer 3 RCA.                                      |
| [observability-stack-setup.md](references/observability-stack-setup.md)         | Optional Prometheus + Grafana config generation — the agent only ever writes config files and never executes Docker lifecycle commands itself.                                                     |

Additional skill-specific references (ingestion parsers, load-profile templates, RCA layer diagnostics) live under each skill's own `references/` folder and are loaded automatically as needed — see the [Project Structure](#project-structure) tree above for the full map.

## Prerequisites

- **[Grafana k6](https://k6.io/docs/get-started/installation/)** ≥ `0.45.0` — the floor required for the `ramping-arrival-rate` executor used by open-system Spike profiles. `hooks/session-start.sh` checks this and fails loudly if it's missing or too old.
- **A POSIX-compatible shell** — macOS Terminal, Linux, WSL, or Git Bash/MSYS2/Cygwin on Windows. Plain `cmd.exe` or a bash-less PowerShell cannot run the session hook at all.
- **Docker** (_optional_) — only needed if you opt into the Prometheus/Grafana observability stack; every other phase of the lifecycle runs without it.

## Why This Suite Exists

AI agents left to their own devices will happily report a latency number they never measured, grade their own load test as "looks good," and quietly extrapolate a 5 VU result to 500 VU because the user asked for a bigger number. This suite exists to make all three of those failure modes structurally impossible rather than relying on the agent remembering not to do them.

Every telemetry-producing phase runs through an adversarial Sub-Agent that never saw the Master's reasoning, only its evidence — so a report can't pass because the agent that wrote it was confident. And before any full-load run touches a live host, a human has to explicitly confirm it's an authorized test target with third-party integrations sandboxed, so "load test the app" can never quietly turn into an unintended denial-of-service against production or someone else's domain — a safety gate genuinely missing from most agent-skill suites.

## Contributing

- Every `SKILL.md` must have exactly the 7 sections above, in order, under 500 lines — push long templates into that skill's own `references/`.
- `description` in frontmatter must start with `"Use when..."` and state the specific triggering condition, not a restatement of the skill's name.
- Any illustrative example using the EShop scenario (search/cart/checkout) must include an explicit note distinguishing the reusable technique from the domain-specific names to substitute.
- `commands/*.md` are thin triggers only — no execution logic or workflow steps beyond naming the persona/skill to invoke.
- See `CLAUDE.md` for the full contributor guide, including the Workspace Boundary Rule and the Master-SubAgent Adversarial Pattern requirements.

## License

This project is licensed under the [MIT License](LICENSE).
