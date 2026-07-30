# CLAUDE.md

Instructions for AI agents **developing, modifying, or contributing** to this repository. This is the contributor guide for the skill suite itself — not for running performance tests against a target application. If you are executing performance testing tasks in a target SUT project, read `AGENTS.md` instead.

## 1. Repository Purpose & Scope

`performance-testing-skills` is a modular, **100% Grafana k6-centric** performance engineering skill suite. It is designed to be integrated into target projects via `git submodule` mounted at that project's `.claude/` directory:

```text
target-project/
├── docs/                             <- INPUT: session.har, spec.md, openapi.json (human-provided)
├── perf-test/                        <- OUTPUT: all generated artifacts (specs, plans, scripts, raw logs, reports)
└── .claude/                          <- this repo, mounted as a submodule (the engine — read-only workspace)
    ├── skills/
    ├── commands/
    ├── agents/
    ├── references/
    └── hooks/
```

Because of this mount point, **this repository must never contain a nested `.claude/` directory of its own**. Command trigger files live at the repository root under `commands/` (e.g. `commands/perf-spec.md`), not `.claude/commands/`. Any contribution that reintroduces a `.claude/` folder at this repo's root must be rejected.

**Workspace Boundary Rule**: `.claude/` is the engine (skill/command/persona/reference definitions), never a workspace. AI Agents executing skills against a target SUT must NOT read or write any artifacts directly inside `.claude/`. All input artifacts (HAR captures, existing specs, OpenAPI documents) must be sourced from `docs/` (or the target project root); all generated output — `PERF_SPEC.md`, task plans, k6 scripts, raw execution logs, and reports — MUST be written to `perf-test/`, never into `.claude/`.

Scope is exclusively **k6 Test-as-Code**. Do not add, reference, or accept content related to Apache JMeter, JVM/GC tuning, GUI-based test plans, XML test definitions, or Groovy scripting. If a contribution imports concepts from those tools, translate them into k6 JavaScript idioms or reject the contribution.

## 2. Skill Design Principles (The 7 Non-Negotiables)

Every skill, command, and persona file in this repository must encode — or at minimum never contradict — these seven rules. They govern how the resulting agent behaves when running performance tests in a target project.

| #   | Principle                       | Rule                                                                                                                                                                                                                                                                                                                                                                      |
| --- | ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | **Never Assume Latency**        | Never state or imply a latency/throughput number that was not measured in the current session. No estimation, no "should be fine," no recall from a prior unrelated run.                                                                                                                                                                                                  |
| 2   | **Enforce Clean Baseline**      | Require a server restart and/or database re-seed before any comparative test. Comparing a warm, polluted state against a cold one invalidates the result.                                                                                                                                                                                                                 |
| 3   | **Measure Before Optimizing**   | Root cause must be proven with runtime data (CPU, RSS, event-loop lag, DB lock waits, k6 trend metrics) before any fix is proposed. No guessing at bottlenecks from code inspection alone.                                                                                                                                                                                |
| 4   | **Surface Assumptions**         | Explicitly declare load profile boundaries (VUs, duration, ramp shape) and SUT architecture limits (e.g. single-process Node.js, SQLite single-writer) before and inside every report.                                                                                                                                                                                    |
| 5   | **Reject Flawed Logic**         | Push back on invalid extrapolation — e.g., linearly projecting 5 VU results to 500 VUs on a SQLite-backed single-writer service. State why the extrapolation is invalid instead of silently complying.                                                                                                                                                                    |
| 6   | **Require Runtime Evidence**    | No step may be marked complete without quantitative proof: an ASCII k6 summary block, a metrics table, or raw log output. Prose claims without attached evidence are not acceptable completions.                                                                                                                                                                          |
| 7   | **Independent Sub-Agent Audit** | No telemetry-producing command (`/perf-verify`, `/perf-audit`, `/perf-gate`) can output a final artifact without first undergoing a verification pass by the `bottleneck-auditor` Sub-Agent, spawned adversarially against the Master Agent's (`perf-architect`) draft findings. A `REJECTED` audit verdict blocks the report; only an `APPROVED` verdict permits output. |

When writing or reviewing a skill file, verify each of the above is reflected in that skill's `Core Process / Workflow`, `Common Rationalizations`, or `Red Flags` sections as relevant.

## 3. Skill File Anatomy Standards

Every `skills/*/SKILL.md` MUST contain exactly these 7 sections, in this order:

```markdown
---
name: <skill-name-matching-directory>
description: <when to use this skill, in 1-2 sentences>
---

# <Skill Title>

## Overview

## When to Use

## Core Process / Workflow

## Common Rationalizations

## Red Flags

## Required Output Format
```

Rules:

- **Frontmatter** `name` must exactly match the containing directory name. `description` must start with `"Use when..."` and state only the specific triggering condition — not a restatement of the skill name, and not general marketing copy.
- **Overview** — 1-2 sentences maximum. No marketing language.
- **When to Use** — concrete trigger conditions (slash command invoked, specific user intent, specific artifact present, e.g. a HAR file).
- **Core Process / Workflow** — numbered, step-by-step. Each step should be independently verifiable.
- **Common Rationalizations** — a two-column table (`Common Agent Rationalization` | `Engineering Reality`) capturing excuses an agent might use to skip rigor, and the correct rebuttal. Minimum 2 rows for a merged skill.
- **Red Flags** — bullet list of observable agent behaviors that indicate the skill is being violated (e.g. "reporting p95 without a threshold pass/fail verdict").
- **Required Output Format** — the enforced structural shape of the skill's output (tables, ASCII blocks, key-value metrics). This section is authoritative — an agent output that doesn't match this shape is non-compliant.

**Illustrative Examples & the EShop Reference Scenario**: any illustrative example inside a `Required Output Format` section may use the EShop reference scenario (search/cart/checkout) for concreteness, but every such example MUST include an explicit note distinguishing the reusable technique (structure, patterns, sourcing rules) from the domain-specific content (route names, entity names) that must be replaced per target project. Without this note, an agent risks pattern-matching the EShop literal route names onto an unrelated target domain (e.g. banking, IoT) instead of substituting that project's actual `In-Scope Routes` from its `PERF_SPEC.md`.

**Context Window Discipline**: every `skills/*/SKILL.md` MUST stay under **500 lines** to protect the LLM's context window. Long templates, elaborate code examples, or deep lookup matrices do not belong inline — push them into a skill-local `skills/<skill-name>/references/` subdirectory and link to them from the relevant section instead of inlining them.

## 4. Formatting Rules for Output Mandates

All skill outputs are **metrics-first**. Applies to every `Required Output Format` section and to actual agent output produced by invoking these skills:

- Prose explanation is capped at **3-5 bullet points** per section. Anything longer belongs in a table or is cut.
- Quantitative results MUST use Markdown tables or fenced ASCII blocks — never paragraphs of narrated numbers.
- Standard metric vocabulary: `RPS`, `p50`, `p90`, `p95`, `p99`, `Error Rate %`. Use these exact labels for consistency across skills.
- k6 execution evidence should be pasted as raw or lightly-trimmed `k6 summary` ASCII output inside a fenced code block, not paraphrased.
- Every gate/decision output (`/perf-verify`, `/perf-audit`, `/perf-gate`) must end in an explicit verdict line (e.g. `RESULT: PASS`, `FINAL GATE DECISION: REJECT`) — never leave the outcome implicit.

## 5. Rules for Adding Commands and Personas

- **`commands/*.md`** — one file per slash command. Filename must match the command name (`commands/perf-spec.md` → `/perf-spec`). **Strict Thin Commands rule**: a command file is a trigger/router ONLY — the instructional prose (steps naming the persona/skill) stays under 10 lines; the fenced Router Status block (per the 9-field template in `using-performance-testing-skills/SKILL.md`) is exempt from this count since it's a templated echo, not execution logic. It must NEVER contain execution logic, workflow steps, or instructions that duplicate what already lives in the target `SKILL.md`. If a command file is explaining _how_ to do something rather than just _which skill handles it_, that content belongs in the skill, not the command.
- **`agents/*.md`** — persona definitions used for role-switching during multi-phase engagements (see `AGENTS.md` § Persona Activation & Sub-Agent Protocol). A new persona is only justified if it represents a genuinely distinct responsibility boundary (e.g. build-phase architect vs. audit-phase investigator), not a cosmetic rename.
- **`references/*.md`** — supporting technical material (cheatsheets, theory, concurrency patterns) that skills may link to but that is not itself a workflow. References must stay k6/JavaScript-centric; do not add tool-specific reference material outside the Grafana k6 ecosystem.
- **`hooks/*`** — session lifecycle automation (e.g. `session-start.sh`). Hooks must be idempotent, side-effect-free on failure, and must not silently swallow errors that would block accurate load testing (e.g. a missing `k6` binary must fail loudly, not warn quietly).

Before adding any new file under `skills/`, `commands/`, `agents/`, `references/`, or `hooks/`, confirm it does not duplicate an existing one and that it is written entirely in English.

### Multi-Agent Execution Pattern (Master-SubAgent Adversarial)

This suite uses a **Master-SubAgent Adversarial Pattern**, not a single monolithic agent, for every telemetry-producing phase:

- **Master Agent** (`agents/perf-architect.md`) — owns execution: runs k6, generates scripts, produces the first draft of any report or telemetry summary. The Master is never the sole judge of its own results during VERIFY, AUDIT, or SHIP.
- **Sub-Agent** (`agents/bottleneck-auditor.md`) — spawned independently during `/perf-verify`, `/perf-audit`, and `/perf-gate`. It receives a fixed payload (target SLOs from `PERF_SPEC.md`, raw execution logs, Master's draft findings) and returns a structured `[AUDIT_FEEDBACK_BLOCK]` with a binary verdict (`APPROVED` / `REJECTED`), any bypassed errors, and required corrections.
- Contributors adding or editing a command/persona that touches VERIFY, AUDIT, or SHIP must preserve this two-agent boundary — do not collapse the Sub-Agent audit into the Master's own narration, and do not let the Master mark a `/perf-verify`, `/perf-audit`, or `/perf-gate` output as final without an `APPROVED` Sub-Agent verdict attached as evidence.
- A `REJECTED` verdict is a hard stop: the Master must revise and resubmit for another audit pass, never override it.
