---
name: script-engineering-and-correlation
description: Use when engineering Grafana k6 scripts, extracting dynamic tokens/correlation, parameterizing test data via SharedArray, or persisting k6 JS files to perf-test/scripts/.
---

# Script Engineering and Correlation

## Overview

Converts `perf-test/PERF_SPEC.md` and `perf-test/PERF_PLAN.md` into complete, production-ready k6 JavaScript scripts — one per declared strategy — with dynamic auth correlation and memory-efficient data parameterization. Owned and executed directly by the Master Agent (`perf-architect`); no Sub-Agent audit gate applies to BUILD (`N/A`) — the script itself is what VERIFY later exercises and audits.

## When to Use

- The `/perf-script` command is invoked.
- After `perf-test/PERF_SPEC.md` and `perf-test/PERF_PLAN.md` both exist and PLAN's Clean Baseline checklist is in place.
- Converting a HAR capture, an OpenAPI document, or codebase-discovered routes into an executable k6 script.
- Re-parameterizing an existing script (new test data, new auth flow, a newly declared strategy) rather than writing one from scratch.

## Core Process / Workflow

1. **Input Contract & JIT Context Resolution.** Read `perf-test/PERF_SPEC.md`'s Engagement Metadata (`Ingestion Source`, `Declared Test Strategy`, `Target SUT Stack`) and `perf-test/PERF_PLAN.md` (task breakdown, architecture limits). **STOP if either file is missing — never build a script against an unestablished spec or plan.** Apply the **JIT Protocol** (`AGENTS.md` §3): load exactly one ingestion parser matching the `Ingestion Source` (`parse-har.md` OR `parse-openapi.md` OR, if neither HAR nor OpenAPI is available, the `parse-codebase.md` fallback), the mandatory `correlation.md`, exactly one `profile-*.md` strategy file per strategy actually declared in `PERF_SPEC.md` (never an undeclared one), and `protocol-http.md`. Leave every non-matching reference file unread, even "just in case."
2. **Dynamic Correlation & Session Engine.** Extract the bearer token/CSRF token from the parsed artifact via regex or JSONPath. Implement the **login-once-per-VU** model — authenticate in `setup()` or on first iteration via a cached per-VU variable, then inject the resulting token into subsequent request headers. Never hardcode a captured token (it expires and represents one real session, not per-VU identity) and never re-authenticate on every iteration (it inflates load-generator-side cost and produces a false request-rate signal — Non-Negotiable 1 and 4).
3. **Memory-Efficient Parameterization.** Load test data referenced from `docs/` via `SharedArray` — never `open()`/`JSON.parse()` inside the default VU iteration function, which re-parses per request and multiplies RAM by VU count. Configure k6 `options` (scenarios, executor, ramp shape) from `PERF_PLAN.md`'s per-strategy workload boundaries, and `thresholds` per endpoint sourced directly from `PERF_SPEC.md`'s SLO matrix — never invent a threshold not backed by the spec.
4. **Multi-Strategy Script Generation.** Generate one complete, standalone k6 script **for every strategy declared** in `PERF_SPEC.md` — each with its own scenario/executor/ramp matching that strategy's Task Breakdown Table row in `PERF_PLAN.md`. Persist each script to `perf-test/scripts/{strategy}.k6.js` (e.g. `perf-test/scripts/baseline.k6.js`, `perf-test/scripts/spike.k6.js`) — never merge multiple strategies into a single file, since VERIFY/AUDIT must be able to loop each strategy's script independently.

## Common Rationalizations

| Common Agent Rationalization | Engineering Reality |
| --- | --- |
| "I'll just hardcode the JWT token I captured from the HAR file, it's simpler." | A captured token expires and is tied to one real session/user — every VU would share one identity and the token will go stale mid-run, invalidating the test. Log in dynamically per VU instead. |
| "I'll log in on every iteration so I never have to worry about token expiry." | Re-authenticating every iteration multiplies the load-generator's own request volume against the auth endpoint, skewing the measured request mix and producing a false signal about where load actually goes. Log in once per VU and cache the token. |
| "I'll load the entire `references/` folder for this skill at once, it's easier than picking files." | The JIT Protocol exists specifically to avoid this — loading unrelated parser/profile/protocol files wastes context and can introduce contradictory guidance for a strategy that isn't even declared this engagement. |
| "I'll write both `baseline` and `spike` into one big script with an `if` on an env var." | VERIFY and AUDIT must loop each declared strategy's script *independently and sequentially*, each with its own raw log and report file — a merged script breaks that per-strategy loop and makes it impossible to VERIFY one strategy without touching the other's code path. |
| "I don't need to check `PERF_PLAN.md`'s architecture limits before writing the script — I'll just write reasonable-looking request logic." | A script that ignores a documented architecture limit (e.g. SQLite single-writer) can misdesign its own concurrency (e.g. parallel writes inside one VU iteration) and produce a self-inflicted bottleneck that AUDIT then misattributes to the SUT. |
| "I'll drop the finished script into `.claude/scripts/` since that's where this suite lives." | `.claude/` is the read-only engine; every generated artifact — including scripts — must be written under the target project's `perf-test/`, never into `.claude/` (Workspace Boundary Rule). |

## Red Flags

- A script contains a literal hardcoded credential, API key, or a single long-lived JWT reused across all VUs.
- The JIT Protocol is violated — a parser, profile, or protocol reference file is loaded for an ingestion source or strategy not actually declared in `PERF_SPEC.md`.
- BUILD proceeds despite `perf-test/PERF_SPEC.md` or `perf-test/PERF_PLAN.md` not existing yet.
- A `SharedArray`-eligible dataset is instead read with `open()`/`JSON.parse()` inside the default VU iteration function.
- The login flow re-authenticates on every iteration instead of once per VU.
- A script's `perf-test/scripts/` filename lacks the `{strategy}` suffix, or two strategies are merged into one file.
- A `thresholds` value in `options` cannot be traced back to a specific row in `PERF_SPEC.md`'s SLO matrix.
- A script or any generated artifact is written outside `perf-test/scripts/` — to the project root, or worse, inside `.claude/`.
- A generated script for a non-EShop target project reuses the example's literal route paths (`/api/search`, `/api/cart`, `/api/checkout`) or group names instead of the routes actually declared in that project's `PERF_SPEC.md`.

## Required Output Format

Persist one complete, standalone, runnable k6 script per declared strategy to `perf-test/scripts/{strategy}.k6.js` — the full file, never a fragment requiring the user to fill in unstated gaps. Example for the `baseline` strategy:

```javascript
// perf-test/scripts/baseline.k6.js
import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { SharedArray } from 'k6/data';

const users = new SharedArray('users', function () {
  return JSON.parse(open('../../docs/users.json'));
});

export const options = {
  scenarios: {
    baseline_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: __ENV.TARGET_VUS || 50 },
        { duration: '10m', target: __ENV.TARGET_VUS || 50 },
        { duration: '1m', target: 0 },
      ],
    },
  },
  thresholds: {
    'http_req_duration{group:::search}': ['p(95)<400'],
    'http_req_duration{group:::cart}': ['p(95)<450'],
    'http_req_duration{group:::checkout}': ['p(95)<900'],
    http_req_failed: ['rate<0.01'],
  },
};

function login(user) {
  const res = http.post(
    `${__ENV.BASE_URL}/api/auth/login`,
    JSON.stringify({ username: user.username, password: user.password }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  check(res, { 'login succeeded': (r) => r.status === 200 });
  return res.json('token');
}

// Module-scope state: k6 gives each VU its own isolated JS execution context,
// so these variables persist across iterations of the same VU but are never
// shared with other VUs — this is what makes login-once-per-VU possible
// without setup().
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

  group('search', function () {
    const res = http.get(`${__ENV.BASE_URL}/api/search?q=shoes`, authHeaders);
    check(res, { 'search status 200': (r) => r.status === 200 });
  });

  group('cart', function () {
    const res = http.post(`${__ENV.BASE_URL}/api/cart`, JSON.stringify({ productId: 42 }), {
      headers: { ...authHeaders.headers, 'Content-Type': 'application/json' },
    });
    check(res, { 'cart status 200': (r) => r.status === 200 });
  });

  group('checkout', function () {
    const res = http.post(`${__ENV.BASE_URL}/api/checkout`, null, authHeaders);
    check(res, { 'checkout status 200/201': (r) => r.status === 200 || r.status === 201 });
  });

  sleep(1);
}
```

**This example illustrates the EShop reference scenario — separate what must be replaced per project from what must not:**

- **Domain-Specific Illustration (replace 1:1 for any real project):** the route paths (`/api/search`, `/api/cart`, `/api/checkout`), the `group()` names, and the request bodies (`{ productId: 42 }`, etc.) exist only to make this example concrete for an EShop-style app. For any actual target — banking, an IoT dashboard, anything else — replace every one of these with the `In-Scope Routes` actually declared in that project's `PERF_SPEC.md`. Never carry over an EShop route literally into an unrelated domain.
- **Generic & Mandatory Techniques (keep unchanged regardless of domain):** the `SharedArray` data-loading structure, the login-once-per-VU session model (module-scope `vuUser`/`vuToken` caching), sourcing every `thresholds` entry from `PERF_SPEC.md`, and sourcing every `scenarios`/`stages` shape from `PERF_PLAN.md`. These are structural rules, not EShop-specific content — they apply identically no matter what the SUT's domain is.

- A second declared strategy (e.g. `spike`) is a **separate file** — `perf-test/scripts/spike.k6.js` — reusing the same `login()`/`SharedArray` pattern but with its own `scenarios`/`stages` matching that strategy's row in `PERF_PLAN.md`'s Task Breakdown Table (e.g. a `ramping-vus` executor spiking 50→500 VU rather than a flat baseline ramp).
- `thresholds` map directly to the SLOs recorded in `PERF_SPEC.md` for the routes in scope; do not invent thresholds not backed by `PERF_SPEC.md`.
- Explanatory prose accompanying the script is capped at 3-5 bullet points — the script itself is the primary artifact.
