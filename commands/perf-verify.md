---
description: Execute 1 VU sanity dry-run and trigger Sub-Agent Audit Gate 1 (invokes smoke-and-sanity-validation skill).
---

# Command: /perf-verify

Trigger for the **VERIFY** phase of the performance testing lifecycle.

1. Confirm `hooks/session-start.sh` has run and passed for this session — STOP immediately if k6 is missing or mismatched.
2. Read `skills/using-performance-testing-skills/SKILL.md` to internalize the 7 Non-Negotiables and Workspace Boundary Rule.
3. Activate persona `agents/perf-architect.md` and execute `skills/smoke-and-sanity-validation/SKILL.md`.

```text
================================================================================
PERFORMANCE SUITE ROUTER STATUS
================================================================================
ACTIVE PHASE      : VERIFY
ACTIVE STRATEGY   : Per active loop strategy (e.g., baseline | spike)
ACTIVE PERSONA    : perf-architect (Master) -> bottleneck-auditor (Sub-Agent Gate 1)
TARGET COMMAND    : /perf-verify
TARGET SKILL      : skills/smoke-and-sanity-validation/SKILL.md
INPUT CONTRACT    : perf-test/scripts/{strategy}.k6.js, perf-test/PERF_PLAN.md
OUTPUT TARGET     : perf-test/logs/{strategy}-verify.log, perf-test/reports/verify-sanity-{strategy}.md
SUB-AGENT GATE    : [ PENDING | APPROVED | REJECTED ] (Gate 1 — Sanity Validation)
7 NON-NEGOTIABLES : [ 1:OK 2:OK 3:OK 4:OK 5:OK 6:OK 7:OK ]
================================================================================
```
