---
description: Run a 1-VU smoke/sanity check on the k6 script before scaling load (invokes smoke-and-sanity-validation skill).
---

# /perf-verify

Route to `skills/smoke-and-sanity-validation/SKILL.md` as the Master Agent (`agents/perf-architect.md`):

1. Execute the k6 script at 1 VU and capture the raw CLI output.
2. Draft the checks-vs-thresholds summary from that raw output.
3. Spawn the `bottleneck-auditor` Sub-Agent (`agents/bottleneck-auditor.md`) with: target SLOs from `PERF_SPEC.md`, the raw execution log, and this draft summary.
4. Do not output the final result to the user until the Sub-Agent returns `AUDIT VERDICT: APPROVED` in its `[AUDIT_FEEDBACK_BLOCK]`. On `REJECTED`, apply the Required Corrections and resubmit for another audit pass before presenting anything.
5. Present the final response with both the raw evidence and the Sub-Agent's `[AUDIT_FEEDBACK_BLOCK]` attached.
