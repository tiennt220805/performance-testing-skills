# Parse OpenAPI (Primary Ingestion #2)

Extracts a k6-ready request list from an `openapi.json`/`swagger.json` document found in `docs/`. Loaded by BUILD's JIT Protocol only when `PERF_SPEC.md`'s `Ingestion Source` metadata points to an OpenAPI/Swagger document.

**Note:** Route paths, field names, and payloads in this file's examples (`/api/cart`, `productId`, etc.) illustrate the EShop reference scenario only — substitute the actual `In-Scope Routes`/fields from the target project's `PERF_SPEC.md`; only the JS patterns (extraction logic, module-scope caching, JIT loading rules) are mandatory to preserve.

## 1. Locate and Load the Spec

Read the document named in `PERF_SPEC.md`'s `Ingestion Source` field. Support both OpenAPI 3.x (`openapi: "3.x"`) and Swagger 2.0 (`swagger: "2.0"`) — the `paths` object shape is functionally equivalent for this purpose; note which version is in use since request-body schema location differs (`requestBody.content['application/json'].schema` in 3.x vs. a `body`-type parameter in 2.0).

## 2. Filter to In-Scope Routes

Cross-reference every path in `paths` against `PERF_SPEC.md`'s `In-Scope Routes` list. **Only generate k6 requests for routes explicitly in scope** — an OpenAPI document commonly describes far more of the API surface than this engagement's SLOs cover (admin endpoints, internal-only routes, deprecated versions). Generating load against out-of-scope routes pollutes the telemetry with traffic nobody asked to measure.

## 3. Extract Method, Parameters, and Schema

For each in-scope `path` + `method` combination:

| OpenAPI field | k6 usage |
|---|---|
| `path` (e.g. `/api/orders/{orderId}`) | Interpolate `{orderId}`-style path parameters with a real or `SharedArray`-sourced value before the request |
| `parameters` (`in: query`/`in: path`/`in: header`) | Build the query string / path substitution / header map accordingly; respect `required: true` |
| `requestBody.content['application/json'].schema` (3.x) or `body` parameter's `schema` (2.0) | Generate a JSON payload matching the schema's declared types (see §4) |
| `responses['200']` (or the documented success code) | Baseline for the script's `check()` |
| `security` / referenced `securitySchemes` | Identify whether the route needs a bearer token, an API key header, or is public — feed this into `correlation.md`'s auth flow |

## 4. Generate Schema-Accurate Dummy Data

Do not invent arbitrary values that ignore the schema's declared types and constraints. For each property in a request body schema:

- `type: "string"`, `format: "email"` → a syntactically valid email, not an arbitrary string.
- `type: "string"`, `enum: [...]` → pick a value from the enum, never an out-of-enum string.
- `type: "integer"`/`"number"` with `minimum`/`maximum` → a value inside the declared bounds.
- `type: "string"`, `format: "date-time"` → a valid ISO-8601 timestamp.
- `required: [...]` fields → always populated; never omitted even for "just testing" purposes, since a missing required field produces a `4xx` that has nothing to do with the SUT's actual performance characteristics.

```javascript
// OpenAPI schema: { type: "object", required: ["productId", "quantity"],
//   properties: { productId: { type: "integer" }, quantity: { type: "integer", minimum: 1 } } }
const cartPayload = JSON.stringify({ productId: 42, quantity: 1 });
```

## 5. Map to k6 Request Structures

```javascript
group('orders', function () {
  const res = http.get(`${__ENV.BASE_URL}/api/orders/${orderId}`, authHeaders);
  check(res, { 'get order status 200': (r) => r.status === 200 });
});
```

Group requests by their OpenAPI `tags` field when present (many specs tag routes by business domain, e.g. `tags: ["orders"]`) — this maps naturally onto k6 `group()` boundaries and keeps AUDIT's later per-flow latency attribution meaningful.

## 6. Flag Schema Gaps Instead of Guessing

If a route's schema is incomplete (missing a request body definition for a `POST`, no declared response schema, an ambiguous `security` requirement), do not silently invent the missing piece. Note the gap explicitly in the BUILD output and, if it blocks generating a correct request, treat it the same as a missing input artifact — surface it rather than fabricating a request shape that isn't backed by the spec.
