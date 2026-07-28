---
description: Produce the final SLO scorecard and PASS/REJECT quality gate decision (invokes slo-reporting-and-insights skill).
---

# /perf-gate

Route to `skills/slo-reporting-and-insights/SKILL.md` as the Master Agent (`agents/perf-architect.md`):

1. Assemble the executive scorecard from the audited `/perf-audit` telemetry and draft a preliminary gate decision.
2. Spawn the `bottleneck-auditor` Sub-Agent (`agents/bottleneck-auditor.md`) with: target SLOs from `PERF_SPEC.md`, the raw execution logs, and this draft scorecard.
3. Do not output the final result to the user until the Sub-Agent returns `AUDIT VERDICT: APPROVED` in its `[AUDIT_FEEDBACK_BLOCK]` and signs off on the gate decision. On `REJECTED`, apply the Required Corrections and resubmit for another audit pass before presenting anything.
4. Present the final response with the scorecard, the Sub-Agent's `[AUDIT_FEEDBACK_BLOCK]`, and an explicit terminal line: `FINAL GATE DECISION: PASS` or `FINAL GATE DECISION: REJECT`.
