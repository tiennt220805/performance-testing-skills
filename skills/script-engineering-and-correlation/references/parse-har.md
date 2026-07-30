# Parse HAR (Primary Ingestion #1)

Extracts a k6-ready request list from a browser-recorded `.har` capture found in `docs/`. Loaded by BUILD's JIT Protocol only when `PERF_SPEC.md`'s `Ingestion Source` metadata points to a `.har` file.

**Note:** Route paths, field names, and payloads in this file's examples (`/api/cart`, `productId`, etc.) illustrate the EShop reference scenario only — substitute the actual `In-Scope Routes`/fields from the target project's `PERF_SPEC.md`; only the JS patterns (extraction logic, module-scope caching, JIT loading rules) are mandatory to preserve.

## 1. Locate and Load the Capture

Read the `.har` file named in `PERF_SPEC.md`'s `Ingestion Source` field (e.g. `docs/checkout-flow.har`). A HAR file is JSON with the shape `{ log: { entries: [...] } }` — each `entries[i]` is one captured HTTP transaction with `request` and `response` objects.

## 2. Filter Out Non-API Noise

Not every captured entry represents backend load. Drop an entry if any of the following hold:

- **Static assets by extension** — `.png`, `.jpg`, `.jpeg`, `.svg`, `.gif`, `.css`, `.js`, `.woff`, `.woff2`, `.ico`, `.map`. These are typically served by a CDN or static host, not the SUT's application logic under test.
- **Third-party/analytics domains** — any `request.url` host that doesn't match the SUT's own domain (analytics beacons, ad trackers, font CDNs, payment-widget iframes not in scope). Cross-reference against `PERF_SPEC.md`'s in-scope routes; if a domain isn't part of the SUT, exclude it unless the engagement explicitly says otherwise.
- **`OPTIONS` preflight requests** — CORS preflight is a browser artifact, not a real backend operation to load-test.

Keep everything else: the actual `GET`/`POST`/`PUT`/`PATCH`/`DELETE` calls to the SUT's own API surface.

## 3. Extract the Request Shape

For each surviving entry, pull out what the k6 script needs:

| HAR field | k6 usage |
|---|---|
| `request.method` | `http.get` / `http.post` / etc. |
| `request.url` | Path + query string — replace the captured host with `${__ENV.BASE_URL}` |
| `request.postData.text` | JSON body — passed to `JSON.stringify()` in the k6 request, with dynamic fields swapped for `correlation.md`-sourced values |
| `request.headers` | Only carry over headers that matter for correctness (`Content-Type`, custom API version headers) — **never** carry over `Cookie` or `Authorization` values verbatim (see §4) |
| `response.status` | Baseline for the script's `check()` — e.g. `res.status === 200` |

## 4. Clean Chrome DevTools Redactions — Never Hardcode

HAR exports frequently emit placeholder or redacted values for sensitive headers:

```json
{ "name": "Authorization", "value": "Bearer [Redacted]" }
```

or an empty `Cookie` string. **Never copy `[Redacted]` or an empty credential literally into the script.** Any `Authorization`, `Cookie`, `X-CSRF-Token`, or session-identifying header must be removed from the static request definition and replaced with the dynamic value produced by `correlation.md`'s login-once-per-VU flow at request time.

## 5. Map to k6 Request Structures

Produce one k6 request call per surviving entry, grouped by business flow (e.g. `group('checkout', ...)` for the sequence of entries belonging to one user journey — see the main `SKILL.md` for `group()` usage). Example mapping:

```javascript
// HAR entry: POST https://shop.example.com/api/cart  { "productId": 42 }
group('cart', function () {
  const res = http.post(`${__ENV.BASE_URL}/api/cart`, JSON.stringify({ productId: 42 }), {
    headers: { ...authHeaders.headers, 'Content-Type': 'application/json' },
  });
  check(res, { 'cart status 200': (r) => r.status === 200 });
});
```

## 6. Identify Dynamic Fields for Correlation

Scan captured request bodies and query strings for values that are clearly session-specific rather than static test data — a cart ID returned by a prior response, a CSRF token, a timestamp/nonce. Hand these off to `correlation.md`'s extraction logic rather than hardcoding the captured literal value; a hardcoded session-specific value will be stale or invalid the moment a different VU or a different run executes the script.
