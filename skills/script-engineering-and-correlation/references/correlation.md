# Correlation (Dynamic Token & Session Engine)

Handles every form of dynamic, runtime-extracted data a k6 script must capture and re-inject into subsequent requests — both **auth correlation** (bearer tokens, CSRF tokens, session IDs, multi-step auth chains, all cached per-VU for the life of the run) and **non-auth business-value correlation** (order IDs, cart IDs, transaction UUIDs returned by one response and consumed by a later request within the same flow — see §7). Loaded unconditionally by BUILD's JIT Protocol for every strategy and every ingestion source — correlation is not optional regardless of whether the source was a HAR capture, an OpenAPI spec, or codebase discovery.

**This file's code samples are the canonical login-once-per-VU pattern.** They must match `SKILL.md`'s `Required Output Format` example exactly in structure — module-scope `vuUser`/`vuToken` state, populated on first use, never re-derived on every iteration. If a change is ever made here, the corresponding example in `SKILL.md` must be updated to match, and vice versa — the two must never drift.

**Note:** Route paths, field names, and payloads in this file's examples (`/api/cart`, `productId`, etc.) illustrate the EShop reference scenario only — substitute the actual `In-Scope Routes`/fields from the target project's `PERF_SPEC.md`; only the JS patterns (extraction logic, module-scope caching, JIT loading rules) are mandatory to preserve.

## 1. Why Login-Once-Per-VU, Never Per-Iteration

k6 gives each VU its own isolated JS execution context (a separate VM). Variables declared at module scope are initialized once per VU and persist across that VU's iterations — but are never shared with other VUs. This is the mechanism that makes "authenticate once, reuse for the rest of this VU's run" possible without a separate `setup()` round-trip per iteration:

- **Per-VU identity**: each VU should behave like one consistent simulated user for the duration of the run, not a different random user on every iteration.
- **Cost**: re-authenticating every iteration multiplies the load-generator's own traffic against the auth endpoint, skewing the measured request mix toward login rather than the flows actually under test.
- **Realism**: real users log in once per session, not once per page view.

```javascript
import http from 'k6/http';
import { check } from 'k6';

function login(user) {
  const res = http.post(
    `${__ENV.BASE_URL}/api/auth/login`,
    JSON.stringify({ username: user.username, password: user.password }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  check(res, { 'login succeeded': (r) => r.status === 200 });
  return res.json('token');
}

// Module-scope state: persists across this VU's iterations, isolated from every other VU.
let vuUser = null;
let vuToken = null;

function getVUSession() {
  if (!vuToken) {
    vuUser = users[Math.floor(Math.random() * users.length)];
    vuToken = login(vuUser);
  }
  return { user: vuUser, token: vuToken };
}

export default function () {
  const { token } = getVUSession();
  const authHeaders = { headers: { Authorization: `Bearer ${token}` } };
  // ...requests using authHeaders
}
```

**Never write a sample or a generated script where `login()` (or an equivalent auth call) is invoked unconditionally inside `export default function()`.** The only exception is the expiry-driven refresh case in §4 — and even then, the call is gated behind an expiry check, never unconditional.

## 2. Extracting Tokens and Session Identifiers

Two extraction mechanisms cover nearly every case encountered in practice:

- **JSONPath-style extraction from a response body** — the token is a field in a JSON response:
  ```javascript
  const token = loginRes.json('token');              // top-level field
  const accessToken = loginRes.json('data.access_token'); // nested field
  ```
- **Regex extraction from a header or a non-JSON body** — the token is embedded in a `Set-Cookie` header, an `X-CSRF-Token` header, or an HTML meta tag:
  ```javascript
  const setCookie = loginRes.headers['Set-Cookie'] || '';
  const sessionMatch = setCookie.match(/session_id=([^;]+)/);
  const sessionId = sessionMatch ? sessionMatch[1] : null;
  ```

Whichever mechanism is used, `check()` the extraction itself, not just the HTTP status — a `200` response with an unexpectedly-shaped body should fail loudly rather than let `undefined` silently propagate into every subsequent request's headers:

```javascript
check(res, {
  'login succeeded': (r) => r.status === 200,
  'token extracted': (r) => !!r.json('token'),
});
```

## 3. CSRF Token Extraction Per Request

Some frameworks issue a **fresh** CSRF token on every state-changing request (or every page-equivalent load), not once at login. In that case the token cannot be cached alongside `vuToken` — it must be re-extracted immediately before the request that needs it, sourced from the *previous* response in the same flow:

```javascript
group('checkout', function () {
  // Step 1: load the page/endpoint that issues a fresh CSRF token for this action.
  const formRes = http.get(`${__ENV.BASE_URL}/api/checkout/form`, authHeaders);
  const csrfToken = formRes.json('csrfToken');
  check(formRes, { 'csrf token issued': (r) => !!r.json('csrfToken') });

  // Step 2: submit using the token extracted from Step 1's response, not a cached one.
  const submitRes = http.post(
    `${__ENV.BASE_URL}/api/checkout/submit`,
    JSON.stringify({ cartId: 'abc123' }),
    { headers: { ...authHeaders.headers, 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json' } }
  );
  check(submitRes, { 'checkout submitted': (r) => r.status === 200 });
});
```

This per-request extraction is *not* a violation of login-once-per-VU — the bearer token/session identity is still cached once per VU (`vuToken`); only the CSRF token, which is scoped to a single state-changing action by design, is re-fetched.

## 4. Multi-Step OAuth / Token Chaining

An OAuth-style flow (authorization code → access token, or a token-exchange endpoint) requires more than one request to reach a usable bearer token. Perform the **entire chain once per VU**, inside the same `getVUSession()`-style gate — never repeat individual steps of the chain on every iteration:

```javascript
function performOAuthLogin(user) {
  // Step 1: exchange credentials for an authorization code.
  const authRes = http.post(
    `${__ENV.BASE_URL}/oauth/authorize`,
    JSON.stringify({ username: user.username, password: user.password, client_id: __ENV.CLIENT_ID }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  check(authRes, { 'auth code issued': (r) => !!r.json('code') });
  const authCode = authRes.json('code');

  // Step 2: exchange the authorization code for an access token.
  const tokenRes = http.post(
    `${__ENV.BASE_URL}/oauth/token`,
    JSON.stringify({ grant_type: 'authorization_code', code: authCode, client_id: __ENV.CLIENT_ID }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  check(tokenRes, { 'access token issued': (r) => !!r.json('access_token') });

  return {
    accessToken: tokenRes.json('access_token'),
    refreshToken: tokenRes.json('refresh_token'),
    expiresAt: Date.now() + tokenRes.json('expires_in') * 1000,
  };
}

let vuSession = null; // { accessToken, refreshToken, expiresAt }

function getVUSession(user) {
  if (!vuSession) {
    vuSession = performOAuthLogin(user);
  }
  return vuSession;
}
```

## 5. Token Refresh Mid-Test (Soak Tests)

For long-duration Soak strategies, a token cached at VU start can expire before the run ends. This is the **one legitimate exception** to "authenticate only once" — but it must be an **expiry-gated conditional refresh**, not an unconditional re-login on every iteration:

```javascript
function getVUSession(user) {
  const bufferMs = 5000; // refresh slightly before actual expiry to avoid a race
  if (!vuSession || Date.now() >= vuSession.expiresAt - bufferMs) {
    vuSession = vuSession && vuSession.refreshToken
      ? refreshAccessToken(vuSession.refreshToken)  // prefer a refresh-token exchange over a full re-login
      : performOAuthLogin(user);
  }
  return vuSession;
}

function refreshAccessToken(refreshToken) {
  const res = http.post(
    `${__ENV.BASE_URL}/oauth/token`,
    JSON.stringify({ grant_type: 'refresh_token', refresh_token: refreshToken, client_id: __ENV.CLIENT_ID }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  check(res, { 'token refreshed': (r) => !!r.json('access_token') });
  return {
    accessToken: res.json('access_token'),
    refreshToken: res.json('refresh_token') || refreshToken,
    expiresAt: Date.now() + res.json('expires_in') * 1000,
  };
}
```

The distinguishing rule: **every call site in this file checks a condition (`!vuToken`, `Date.now() >= expiresAt - buffer`) before calling into the auth flow.** A generated script where the auth/login function is called with no guard at the top of `export default function()` is non-compliant, regardless of which of these four patterns (simple login, per-request CSRF, OAuth chaining, or expiry refresh) is in use.

## 6. Session ID / Cookie-Based Auth (Non-Bearer)

Some SUTs use server-side session cookies instead of a bearer token. k6's `http` client persists cookies automatically within a VU when a `CookieJar` is used (the default jar behaves per-VU, matching the same isolation guarantee bearer tokens rely on) — authenticate once per VU via the same gated pattern, and let subsequent requests rely on the automatically-attached session cookie rather than manually re-attaching a header on every call:

```javascript
const jar = http.cookieJar();

function getVUSession(user) {
  if (!vuUser) {
    vuUser = user;
    const res = http.post(`${__ENV.BASE_URL}/login`, JSON.stringify({ username: user.username, password: user.password }), {
      headers: { 'Content-Type': 'application/json' },
    });
    check(res, { 'login succeeded': (r) => r.status === 200 });
  }
  return vuUser;
}
```

## 7. Non-Auth Business-Value Correlation (Flow / Session Chaining)

Not every dynamic value flowing through a script is auth-related. A business flow frequently returns an entity ID from one step that a later step in the *same flow* must reuse — an `orderId` from `POST /api/orders`, a `cartId` from `POST /api/cart`, a `transactionUuid` from a payment-initiation call. This is a distinct correlation category from auth tokens and has a different lifetime.

**Architectural boundary — this is the critical distinction from §1–§6:**

| | Auth Tokens / Session (§1–§6) | Business-Value IDs (§7) |
|---|---|---|
| Cache scope | Module-scope, **per-VU**, for the life of the run | **Per-flow / per-iteration** — a plain local variable inside the iteration function or `group()` |
| Lifetime | Survives across many iterations of the same VU | Reset (re-fetched or newly created) on every iteration; never carried over to the next iteration |
| Cached via | `let vuToken = null;` at module scope, populated once | `const orderId = ...;` declared fresh inside `export default function()` or the `group()` block |
| Why it differs | One simulated user keeps one identity for the whole run | A new order/cart/transaction is a distinct entity each time the flow runs — reusing yesterday's `orderId` in today's iteration doesn't represent real usage and can 404 or corrupt state |

**Never cache a business-value ID at module scope like `vuToken`.** Doing so means every iteration of that VU replays against the *same* order/cart/transaction instead of creating and operating on a new one each time — this silently narrows the load profile to a single entity's read path and stops exercising the SUT's write path entirely.

```javascript
export default function () {
  const { token } = getVUSession();
  const authHeaders = { headers: { Authorization: `Bearer ${token}` } };

  group('order-flow', function () {
    // Step 1: create a new order — the response's orderId is scoped to this iteration only.
    const createRes = http.post(
      `${__ENV.BASE_URL}/api/orders`,
      JSON.stringify({ productId: 42, quantity: 1 }),
      { headers: { ...authHeaders.headers, 'Content-Type': 'application/json' } }
    );
    check(createRes, { 'order created': (r) => r.status === 201 && !!r.json('orderId') });
    const orderId = createRes.json('orderId'); // local to this iteration — never module-scope

    // Step 2: reuse the orderId from Step 1 within the same flow.
    const statusRes = http.get(`${__ENV.BASE_URL}/api/orders/${orderId}`, authHeaders);
    check(statusRes, { 'order status retrievable': (r) => r.status === 200 });
  });
  // Next iteration of this same VU creates a brand-new order and gets a brand-new orderId —
  // orderId is never reused across iterations, unlike vuToken.
}
```

Apply the same per-flow (not per-VU) scoping to any chained business identifier: a `cartId` threaded through add-item → update-quantity → checkout, or a `transactionUuid` threaded through initiate-payment → confirm-payment → receipt. Extract each via the same JSONPath/regex mechanisms from §2 — the extraction technique is identical between auth and business-value correlation; only the caching lifetime differs.
