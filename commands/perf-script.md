---
description: Engineer Grafana k6 performance testing scripts with dynamic correlation (invokes script-engineering-and-correlation skill).
---

# Command: /perf-script

Trigger for the **BUILD** phase of the performance testing lifecycle.

1. Confirm `hooks/session-start.sh` has run and passed for this session — STOP immediately if k6 is missing or mismatched.
2. Read `skills/using-performance-testing-skills/SKILL.md` to internalize the 7 Non-Negotiables and Workspace Boundary Rule.
3. Activate persona `agents/perf-architect.md` and execute `skills/script-engineering-and-correlation/SKILL.md`.

```text
================================================================================
PERFORMANCE SUITE ROUTER STATUS
================================================================================
ACTIVE PHASE      : BUILD
ACTIVE STRATEGY   : Per declared strategy in PERF_SPEC.md
ACTIVE PERSONA    : perf-architect (Master)
TARGET COMMAND    : /perf-script
TARGET SKILL      : skills/script-engineering-and-correlation/SKILL.md
INPUT CONTRACT    : perf-test/PERF_SPEC.md, perf-test/PERF_PLAN.md, docs/
OUTPUT TARGET     : perf-test/scripts/*.k6.js
SUB-AGENT GATE    : N/A (BUILD phase)
7 NON-NEGOTIABLES : [ 1:OK 2:OK 3:OK 4:OK 5:OK 6:OK 7:OK ]
================================================================================
```
