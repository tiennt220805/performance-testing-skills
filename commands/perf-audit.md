---
description: Execute full load performance test and trigger Sub-Agent Audit Gate 2 (invokes bottleneck-root-cause-analysis skill).
---

# Command: /perf-audit

Trigger for the **AUDIT** phase of the performance testing lifecycle.

1. Confirm `hooks/session-start.sh` has run and passed for this session — STOP immediately if k6 is missing or mismatched.
2. Read `skills/using-performance-testing-skills/SKILL.md` to internalize the 7 Non-Negotiables and Workspace Boundary Rule.
3. Activate persona `agents/perf-architect.md` and execute `skills/bottleneck-root-cause-analysis/SKILL.md`.

```text
================================================================================
PERFORMANCE SUITE ROUTER STATUS
================================================================================
ACTIVE PHASE      : AUDIT
ACTIVE STRATEGY   : Per active loop strategy (e.g., baseline | spike)
ACTIVE PERSONA    : perf-architect (Master) -> bottleneck-auditor (Sub-Agent Gate 2)
TARGET COMMAND    : /perf-audit
TARGET SKILL      : skills/bottleneck-root-cause-analysis/SKILL.md
INPUT CONTRACT    : perf-test/scripts/{strategy}.k6.js, perf-test/reports/verify-sanity-{strategy}.md, perf-test/PERF_SPEC.md, perf-test/PERF_PLAN.md
OUTPUT TARGET     : perf-test/logs/{strategy}-audit.log, perf-test/reports/audit-rca-{strategy}.md
SUB-AGENT GATE    : [ PENDING | APPROVED | REJECTED ] (Gate 2 — Full Load & 4-Layer RCA Audit)
7 NON-NEGOTIABLES : [ 1:OK 2:OK 3:OK 4:OK 5:OK 6:OK 7:OK ]
================================================================================
```
