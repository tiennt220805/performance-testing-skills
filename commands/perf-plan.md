---
description: Plan performance testing tasks, verify environment parity, and enforce clean baseline reset (invokes test-environment-and-baseline skill).
---

# Command: /perf-plan

Trigger for the **PLAN** phase of the performance testing lifecycle.

1. Confirm `hooks/session-start.sh` has run and passed for this session — STOP immediately if k6 is missing or mismatched.
2. Read `skills/using-performance-testing-skills/SKILL.md` to internalize the 7 Non-Negotiables and Workspace Boundary Rule.
3. Activate persona `agents/perf-architect.md` and execute `skills/test-environment-and-baseline/SKILL.md`.

```text
================================================================================
PERFORMANCE SUITE ROUTER STATUS
================================================================================
ACTIVE PHASE      : PLAN
ACTIVE STRATEGY   : N/A (Environment setup & planning phase)
ACTIVE PERSONA    : perf-architect (Master)
TARGET COMMAND    : /perf-plan
TARGET SKILL      : skills/test-environment-and-baseline/SKILL.md
INPUT CONTRACT    : perf-test/PERF_SPEC.md + Live SUT environment
OUTPUT TARGET     : perf-test/PERF_PLAN.md
SUB-AGENT GATE    : N/A (PLAN phase)
7 NON-NEGOTIABLES : [ 1:OK 2:OK 3:OK 4:OK 5:OK 6:OK 7:OK ]
================================================================================
```
