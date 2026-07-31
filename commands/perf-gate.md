---
description: Synthesize multi-strategy scorecard and trigger Sub-Agent Audit Gate 3 Sign-off (invokes slo-reporting-and-insights skill).
---

# Command: /perf-gate

Trigger for the **SHIP** phase of the performance testing lifecycle.

1. Confirm `hooks/session-start.sh` has run and passed for this session — STOP immediately if k6 is missing or mismatched.
2. Read `skills/using-performance-testing-skills/SKILL.md` to internalize the 7 Non-Negotiables and Workspace Boundary Rule.
3. Activate persona `agents/perf-architect.md` and execute `skills/slo-reporting-and-insights/SKILL.md`.

```text
================================================================================
PERFORMANCE SUITE ROUTER STATUS
================================================================================
ACTIVE PHASE      : SHIP
ACTIVE STRATEGY   : ALL (aggregates every declared strategy at once)
ACTIVE PERSONA    : perf-architect (Master) -> bottleneck-auditor (Sub-Agent Gate 3)
TARGET COMMAND    : /perf-gate
TARGET SKILL      : skills/slo-reporting-and-insights/SKILL.md
INPUT CONTRACT    : perf-test/reports/audit-rca-*.md, perf-test/PERF_SPEC.md
OUTPUT TARGET     : perf-test/reports/final-gate-scorecard.md
SUB-AGENT GATE    : [ PENDING | APPROVED | REJECTED ] (Gate 3 — Final Gate Sign-off)
7 NON-NEGOTIABLES : [ 1:OK 2:OK 3:OK 4:OK 5:OK 6:OK 7:OK ]
================================================================================
```
