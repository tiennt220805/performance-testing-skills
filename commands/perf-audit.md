---
description: Analyze load test telemetry for bottlenecks and root causes (invokes bottleneck-root-cause-analysis skill).
---

# /perf-audit

Route to `skills/bottleneck-root-cause-analysis/SKILL.md` as the Master Agent (`agents/perf-architect.md`):

1. Execute the full load profile (e.g. 5 VU) and capture the raw CLI output.
2. Draft the baseline-vs-actual telemetry table and error distribution signature from that raw output.
3. Spawn the `bottleneck-auditor` Sub-Agent (`agents/bottleneck-auditor.md`) with: target SLOs from `PERF_SPEC.md`, the raw execution log, and this draft report — instruct it to perform the 4-layer stack audit (Client, Event Loop, SQLite Write Lock, Hardware).
4. Do not output the final result to the user until the Sub-Agent returns `AUDIT VERDICT: APPROVED` in its `[AUDIT_FEEDBACK_BLOCK]`. On `REJECTED`, apply the Required Corrections and resubmit for another audit pass before presenting anything.
5. Present the final response with both the raw evidence and the Sub-Agent's `[AUDIT_FEEDBACK_BLOCK]` attached.
