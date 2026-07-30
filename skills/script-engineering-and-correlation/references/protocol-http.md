# HTTP Protocol Standardization

Standardizes how every k6 script in this suite calls, tags, checks, and classifies errors for generic REST/HTTP requests. **This file does not handle auth or session state** — that is exclusively `correlation.md`'s scope; this file governs the transport-layer mechanics common to every request regardless of whether it's authenticated. Loaded unconditionally by BUILD's JIT Protocol for every engagement, since HTTP is currently the only fully-implemented protocol module in this suite (`protocol-grpc.md`/`protocol-websocket.md`/`protocol-browser.md` remain stubs for future non-HTTP SUTs — `PERF_SPEC.md`'s Engagement Metadata has no `Declared Protocol` field today, so this file's loading is not conditioned on one).

**Note:** Route paths, field names, and payloads in this file's examples (`/api/cart`, `productId`, etc.) illustrate the EShop reference scenario only — substitute the actual `In-Scope Routes`/fields from the target project's `PERF_SPEC.md`; only the JS patterns (executor configurations, threshold structures, JIT loading rules) are mandatory to preserve.

## 1. Request Tagging — `group()` as the Primary Mechanism, `tags.name` as a Dynamic-Path Supplement

**`group()` is the mandatory, primary tagging mechanism for every request.** All four `profile-*.md` files write their thresholds as `'http_req_duration{group:::search}'` — this only resolves correctly if every request in the script is wrapped in a `group()` matching its route/flow, mapped 1:1 to `PERF_SPEC.md`'s `In-Scope Routes`. A request issued outside any `group()` cannot be threshold-checked per-route and silently falls into an ungrouped catch-all metric.

**The problem `group()` alone doesn't solve: dynamic path parameters.** When a route has a path parameter (e.g. `/api/orders/{orderId}`), calling `http.get()` against the *interpolated* URL (`/api/orders/123`, `/api/orders/456`, …) causes k6 to default-tag each request by its literal URL — fragmenting one logical route into as many metrics as there are distinct IDs requested, which breaks threshold aggregation for that route.

**The fix: `tags: { name: '<static template path>' }`, supplementing `group()`, never replacing it.** Use the un-interpolated path template as the tag value, so every call against `/api/orders/{anything}` collapses back into one metric series:

```javascript
import http from 'k6/http';
import { check, group } from 'k6';

function getOrder(orderId, authHeaders) {
  return group('orders', function () {
    const res = http.get(`${__ENV.BASE_URL}/api/orders/${orderId}`, {
      headers: authHeaders.headers,
      tags: { name: 'GET /api/orders/{orderId}' }, // static template — supplements group(), prevents per-ID metric fragmentation
    });
    check(res, {
      'get order status 200': (r) => r.status === 200,
      'order response has expected shape': (r) => !!r.json('orderId'),
    });
    return res;
  });
}
```

Every route with a dynamic segment gets this same two-layer treatment: `group()` for the business-flow boundary, `tags.name` for collapsing the per-instance URL variance back into one series.

## 2. Error Classification Engine

Every response falls into exactly one of three diagnostic classes, each pointing to a different layer of the 4-layer RCA stack `bottleneck-auditor.md` uses during AUDIT:

| Class | Status range | Diagnostic meaning |
|---|---|---|
| `CLIENT_ERROR` | `4xx` | A malformed request or a failed authorization check — a **script or auth defect**, not a SUT bottleneck. Still must be logged so AUDIT can separate "the script is wrong" from "the SUT is slow/broken." |
| `SERVER_ERROR` | `5xx` | The SUT itself failed to handle a well-formed request — a genuine bottleneck signal, typically **Layer 2 (Application)** or **Layer 3 (Data)**. |
| `NETWORK_FAILURE` | `status === 0` | k6 never received a response at all — timeout, connection reset, DNS/TLS failure. Typically a **Layer 1 (Transport)** signal, on either the load-generator or SUT-network side, not a SUT application defect. |

```javascript
function classifyResponse(res) {
  if (res.status === 0) {
    return { errorClass: 'NETWORK_FAILURE', likelyLayer: 'Layer 1 — Transport' };
  }
  if (res.status >= 500) {
    return { errorClass: 'SERVER_ERROR', likelyLayer: 'Layer 2/3 — Application or Data' };
  }
  if (res.status >= 400) {
    return { errorClass: 'CLIENT_ERROR', likelyLayer: 'N/A — script/auth defect, not a SUT bottleneck' };
  }
  return { errorClass: 'SUCCESS', likelyLayer: null };
}
```

Use `classifyResponse(res)` anywhere a script needs to log or tally errors by class — e.g. a custom `Counter` per `errorClass` — so AUDIT's raw-log inspection can separate these three categories without re-deriving the classification from scratch.

## 3. Check Wrappers — Exact Status Codes, Never a Loose Range

`bottleneck-auditor.md`'s Payload Inspection Protocol names this exact failure mode as a bypassed-error signature to hunt for: *"Unhandled `401`/`403` responses silently counted as successful iterations by a loose `check()`."* This file exists to prevent that defect from ever being written in the first place.

**Never check a range or a negation** (`r.status < 400`, `r.status < 500`, `r.status !== 500`) — every one of these silently treats a `401`/`403`/`404` as a pass. **Always check the exact expected status code(s):**

```javascript
// ANTI-PATTERN — do not use. This "passes" on 401, 403, and 404 alike, silently
// miscounting an auth failure or a not-found response as a successful iteration.
check(res, { 'order retrieved': (r) => r.status < 500 });

// CORRECT — checks the exact expected status code, nothing else.
check(res, { 'order retrieved (200)': (r) => r.status === 200 });
```

**A `200` with an empty or malformed body is still a failure — check the body shape too, not status alone** (Non-Negotiable 6, Require Runtime Evidence: a passing status code is not sufficient runtime evidence that the response was actually correct):

```javascript
check(res, {
  'order retrieved (200)': (r) => r.status === 200,
  'order response has expected shape': (r) => {
    const body = r.json();
    return !!body && typeof body.orderId !== 'undefined' && typeof body.status !== 'undefined';
  },
});
```

Only add a body-shape check when `PERF_SPEC.md`/the route's schema actually declares a response shape to verify against — do not invent an assertion about fields the spec never described.

When multiple status codes are valid successes for one route (e.g. a `checkout` route returning `200` or `201`), check against an explicit allow-list array — `[200, 201].includes(r.status)` — never widen back into a range check to accommodate the second code.

## 4. Header Management & Timeout/Retry Config

- **`Content-Type: application/json`** on every `POST`/`PUT`/`PATCH` carrying a body — never omitted, never left to the SUT's default-content-type assumption.
- **A dedicated `User-Agent` for load-test traffic** — e.g. `k6-perf-test/{{strategy}}` (resolving to something like `k6-perf-test/baseline` at BUILD time). This lets SUT-side logs and APM tooling filter load-test traffic out from real user traffic when AUDIT needs to cross-reference k6's client-side telemetry against server-side observability data.

```javascript
const genericHeaders = {
  'Content-Type': 'application/json',
  'User-Agent': `k6-perf-test/{{strategy}}`,
};
```

- **Boundary with `correlation.md`: this file never manages identity headers.** `Authorization`, `Cookie`, and `X-CSRF-Token` are exclusively `correlation.md`'s responsibility via its login-once-per-VU flow — do not duplicate or reimplement that logic here. A request combines both: generic headers from this file, identity headers from `correlation.md`'s session object.
- **Set an explicit `timeout` on any route with abnormally slow expected latency.** Without one, a single hung request can block that VU indefinitely, silently collapsing its effective throughput for the rest of the run and skewing the measured request rate downward without ever surfacing as a clean error:

```javascript
const res = http.get(`${__ENV.BASE_URL}/api/reports/export`, {
  headers: { ...genericHeaders, ...authHeaders.headers },
  tags: { name: 'GET /api/reports/export' },
  timeout: '{{DERIVED_TIMEOUT_MS}}ms', // internal heuristic default = 3x this route's p99 SLO target from PERF_SPEC.md's SLO matrix, computed by BUILD when generating the script — PERF_SPEC.md itself has no "Timeout" column, so this is never sourced as if it were a stakeholder-confirmed SLO field
});
```
