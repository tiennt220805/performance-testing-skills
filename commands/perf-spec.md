---
description: Define performance requirements and SLOs for target endpoints (invokes perf-requirements-and-slo skill).
---

# Command: /perf-spec

Trigger for the **DEFINE** phase of the performance testing lifecycle.

1. Confirm `hooks/session-start.sh` has run and passed for this session — STOP immediately if k6 is missing or mismatched.
2. Read `skills/using-performance-testing-skills/SKILL.md` to internalize the 7 Non-Negotiables and Workspace Boundary Rule.
3. Activate persona `agents/perf-architect.md` and execute `skills/perf-requirements-and-slo/SKILL.md`.

```text
================================================================================
PERFORMANCE SUITE ROUTER STATUS
================================================================================
ACTIVE PHASE      : DEFINE
ACTIVE STRATEGY   : N/A (Spec definition phase)
ACTIVE PERSONA    : perf-architect (Master)
TARGET COMMAND    : /perf-spec
TARGET SKILL      : skills/perf-requirements-and-slo/SKILL.md
INPUT CONTRACT    : docs/ (.har, spec.md, openapi.json)
OUTPUT TARGET     : perf-test/PERF_SPEC.md
SUB-AGENT GATE    : N/A (DEFINE phase)
7 NON-NEGOTIABLES : [ 1:OK 2:OK 3:OK 4:OK 5:OK 6:OK 7:OK ]
================================================================================
```
