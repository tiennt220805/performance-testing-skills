# Layer 1: Transport, Network & Client-Side

**Note:** Route paths, field names, and figures in this file's examples (`/api/cart`, `productId`, `{{...}}` values, etc.) illustrate the EShop reference scenario only — substitute the actual `In-Scope Routes`/fields from the target project's `PERF_SPEC.md`; only the diagnostic technique (metrics to collect, verification commands, layer-attribution logic) is mandatory to preserve.

Loaded unconditionally, together with the other three layer files, during AUDIT Step 3 — every full-load AUDIT run inspects all 4 layers regardless of where the suspected bottleneck lies (Non-Negotiable 3, `bottleneck-auditor.md`'s 4-layer enforcement). This differs from the Strategy Audit Matrix files (`rca-load-stress.md`/`rca-spike.md`/`rca-soak.md`), which ARE conditionally JIT-selected — exactly one, matching the declared strategy. The 4 layer files are never conditionally selected.

## Scope

TCP socket exhaustion, TLS handshake latency, HTTP/1.1 vs. HTTP/2 connection pooling/multiplexing, DNS lookup lag, and — critically — the load generator's own resource constraints producing false-positive SUT latency.

## 1. Symptom Telemetry Signatures

- `http_req_blocked` (time waiting for a free connection slot) elevated across many requests — connection-pool exhaustion, usually on the load-generator side.
- `http_req_connecting` elevated — the TCP handshake itself is slow (network congestion, or the SUT's accept queue backing up).
- `http_req_tls_handshaking` elevated — TLS negotiation overhead, often an undersized keep-alive config or certificate-chain validation cost.
- Explicit error strings in the raw log: `ECONNRESET`, `ETIMEDOUT`, `dial tcp: connection refused`, `context deadline exceeded`.
- `checks` failing not on business logic but on `status === 0` — k6 never received a response at all.

## 2. Diagnostic Metrics & Verification Commands

**k6-observable (always available, no extra access required):** `http_req_blocked`, `http_req_connecting`, `http_req_tls_handshaking` percentiles from the raw `k6 summary` output — these ship with every run, no additional tooling needed.

**OS/host-level — only when the Master has direct access to the SUT host.** Do not fabricate a value that wasn't actually measured; if that access isn't available, write `No direct OS access — inferring from k6-observable signals only` in the report rather than guessing a number (Non-Negotiable 1 applies to every runtime metric, not only latency):

- `netstat -s | grep -i retrans` — TCP retransmission counts, a sign of network-level congestion.
- `ss -s` — socket summary; checks for `TIME_WAIT` exhaustion on either the client or SUT host.
- `ulimit -n` on the load-generator host — confirms the k6 process itself wasn't capped below the concurrency the test needed (a common false-positive source).

## 3. Load-Generator-Side vs. SUT-Side Bottleneck — the Layer 1 Core Job

`bottleneck-auditor.md` states this layer's job explicitly: *"separate 'the load generator is the bottleneck' from 'the SUT is the bottleneck' before blaming the SUT for anything."* The concrete test:

- **`http_req_blocked` elevated + SUT-side CPU/RSS reading low (or unavailable with no other-layer signal)** → suspect the load generator, not the SUT. The k6 process itself is queuing requests waiting for a free connection slot — a load-generator capacity problem, not a SUT one.
- **`http_req_connecting`/`http_req_tls_handshaking` elevated + Layer 2/3 also showing SUT-side saturation at the same time** → the SUT genuinely can't accept new connections fast enough because it's already saturated downstream — a real Layer 1 symptom of a Layer 2/3 root cause, not a load-generator artifact.

Never conclude "Layer 1 bottleneck" from `http_req_blocked` alone without checking whether the load generator itself was under-provisioned for the target VU count.

## 4. Distinction from Other Layers

- A `5xx` response is **not** a Layer 1 signal — the SUT received and processed the request, just badly (Layer 2/3). Only `status === 0` (no response at all) or an explicit connection-level error belongs here.
- Elevated `http_req_waiting` (time-to-first-byte *after* the connection succeeded) is a Layer 2/3 signal, not Layer 1 — the transport succeeded; what's slow is the SUT's processing after that point.

## 5. Worked Example — Ruling a Signal In vs. Out

**Case A — false positive, load-generator-side:**

```text
Raw log excerpt (perf-test/logs/spike-audit.log):
  http_req_blocked.............: avg=812ms  min=0s   med=45ms  max=4.2s  p(90)=2.1s  p(95)=3.4s
  http_req_connecting..........: avg=12ms   min=0s   med=8ms   max=95ms  p(90)=22ms  p(95)=31ms

Load-generator host check: `ulimit -n` returns 1024, while the spike ramp targets 500 concurrent
VUs each holding 2+ connections — past the descriptor ceiling well before the SUT is even reached.
```

`http_req_blocked` p95 (3.4s) is wildly disproportionate to `http_req_connecting` p95 (31ms) — once a connection slot is actually acquired, the handshake itself is fast. The delay is entirely in *acquiring* a slot, and the load-generator's own file-descriptor ceiling explains why. **Verdict: load-generator connection-pool exhaustion, not a SUT bottleneck** — the fix is raising `ulimit -n` on the load-generator host, not touching the SUT.

**Case B — real signal, SUT-side:**

```text
Raw log excerpt (perf-test/logs/baseline-audit.log):
  http_req_connecting..........: avg=340ms  min=5ms  med=280ms  max=1.9s  p(90)=810ms  p(95)=1.1s
  http_req_blocked..............: avg=18ms   min=0s   med=9ms    max=140ms p(90)=35ms   p(95)=52ms
```

Here `http_req_blocked` is unremarkable, but `http_req_connecting` itself is elevated — the load generator isn't queuing for a slot, the TCP handshake is genuinely slow. Correlated with a Layer 4 finding of CPU saturation on the SUT host at the same timestamp (accept-queue backlog under CPU pressure), this is a real Layer 1 symptom whose root cause lives at Layer 4 — the remediation belongs to whichever layer's evidence explains *why* the SUT was slow to accept, not to Layer 1 itself.

## 6. Remediation Boundaries

Only propose fixes the evidence directly supports:

- Confirmed load-generator connection-pool exhaustion → increase k6's VU distribution across multiple load-generator instances, or raise the load-generator host's file-descriptor ulimit — do not touch the SUT.
- Confirmed SUT-side accept-queue saturation (evidenced by correlating Layer 2/4 signals) → defer the actual fix recommendation to whichever layer's evidence explains *why* the SUT couldn't accept connections fast enough; Layer 1 only reports the symptom, not the underlying cause.

## 7. Feeding the RCA Matrix

Reduce this section to exactly one `Evidence` / `Verdict` row in `SKILL.md`'s 4-Layer RCA Inspection Matrix — e.g. `Evidence: http_req_blocked p95 {{VALUE}}ms across {{N}} requests, load-generator ulimit confirmed at {{ULIMIT_VALUE}}` / `Verdict: Root cause — load-generator connection pool exhaustion`, or `Verdict: No signal at this layer`. Any `ECONNRESET`/`ETIMEDOUT`/connection-reset count discovered here maps to the Error Signature Distribution table's "Connection reset / timeout" row, attributed to Layer 1 — Transport.
