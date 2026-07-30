# Parse Codebase (Fallback Ingestion)

Discovers routes directly from the SUT's source code when `docs/` contains neither a `.har` capture nor an `openapi.json`/`swagger.json` document. Loaded by BUILD's JIT Protocol only as the fallback — `parse-har.md` and `parse-openapi.md` are always preferred when either artifact is available, since a live capture or a maintained spec is more reliable than static route discovery.

**Note:** Route paths, field names, and payloads in this file's examples (`/api/cart`, `productId`, etc.) illustrate the EShop reference scenario only — substitute the actual `In-Scope Routes`/fields from the target project's `PERF_SPEC.md`; only the JS patterns (extraction logic, module-scope caching, JIT loading rules) are mandatory to preserve.

## 1. Confirm the Fallback Is Actually Needed

Before scanning source, re-confirm `docs/` genuinely has neither artifact — do not reach for codebase scanning just because it seems faster. If `docs/` is entirely empty, that is a DEFINE-phase problem (`perf-requirements-and-slo/SKILL.md` should have already stopped and asked the user), not something this fallback should paper over.

## 2. Identify the SUT Stack

Use the `Target SUT Stack` metadata from `PERF_SPEC.md` to pick the right scanning approach. Common patterns:

| Stack | Where routes live | What to grep for |
|---|---|---|
| Node.js / Express | Router files (`routes/*.js`, `app.js`) | `router.get(`, `router.post(`, `app.get(`, `app.post(`, etc. |
| Node.js / Fastify | Route plugin files | `fastify.get(`, `fastify.post(`, or `server.route({ method: ... })` |
| Java / Spring | Controller classes | `@GetMapping`, `@PostMapping`, `@RequestMapping(method = ...)`, class-level `@RequestMapping("/api/...")` prefix |
| Python / FastAPI | Router modules | `@app.get(`, `@app.post(`, `@router.get(`, etc., plus `Depends(...)` for auth requirements |
| Python / Flask | Route decorators | `@app.route(`, `methods=[...]` |

## 3. Extract Route Metadata from Source

For each discovered route, extract what a HAR/OpenAPI parse would have given directly:

- **Path and method** — including path parameters (`:id` in Express, `{id}` in Spring/FastAPI-style).
- **Request body shape** — inspect the handler's validation layer (a Joi/Zod schema in Node, a `@RequestBody` DTO class in Spring, a Pydantic model in FastAPI) rather than the handler body's ad-hoc field access, since the validation schema is the authoritative contract.
- **Auth requirement** — a route behind `authMiddleware`/`@PreAuthorize`/`Depends(get_current_user)` needs a token; a route with no such guard is public. Misclassifying this either produces spurious `401`s in the script or under-tests an endpoint that should have been authenticated. Hand off every route flagged as requiring auth to `correlation.md`'s login-once-per-VU flow — never wire a token into the request manually here.
- **Response shape** — enough to write a meaningful `check()` (status code at minimum; a key field to confirm the response body is well-formed if easily discoverable).

## 4. Prioritize by Business Criticality, Not Discovery Order

A codebase scan can surface far more routes than are actually in scope for this engagement (internal health checks, admin CRUD, debug endpoints). Cross-reference discovered routes against `PERF_SPEC.md`'s `In-Scope Routes` list — generated requests are limited to that list, exactly as with the HAR/OpenAPI parsers. Do not silently expand scope just because a route was easy to find.

## 5. Map to k6 Request Structures

Identical target shape to the other two ingestion paths — the parser's job ends at producing a normalized `{ method, path, body schema, auth requirement, group name }` record per in-scope route; script generation and correlation wiring proceed the same way regardless of ingestion source (see `SKILL.md` Core Process Steps 2–4).

```javascript
// Discovered: router.post('/api/cart', authMiddleware, cartController.addItem)
// Validation schema: { productId: Joi.number().required(), quantity: Joi.number().min(1).required() }
group('cart', function () {
  const res = http.post(`${__ENV.BASE_URL}/api/cart`, JSON.stringify({ productId: 42, quantity: 1 }), {
    headers: { ...authHeaders.headers, 'Content-Type': 'application/json' },
  });
  check(res, { 'cart status 200': (r) => r.status === 200 });
});
```

## 6. Flag Ambiguity Instead of Guessing

Static analysis is inherently lossier than a real capture or a maintained spec — a handler's actual runtime behavior (conditional fields, feature-flagged branches, undocumented required headers) may not be fully visible from source alone. When a route's request shape can't be determined with confidence from the code, say so explicitly in the BUILD output rather than fabricating a plausible-looking payload — an incorrect guess produces a script that either fails outright or, worse, passes checks against the wrong contract and produces misleading telemetry later.
