# Observability Stack Setup (Prometheus + Grafana)

Note: Ports, service names, and dashboard IDs in this file are the actual default configuration to generate — unlike other reference files, these are not `{{...}}` illustrative placeholders; the generated `docker-compose.yml` must be immediately runnable as-is.

**Absolute boundary — repeated here because it governs every section below:** the agent's role in this feature is strictly limited to generating configuration files (`docker-compose.yml`, `prometheus.yml`, Grafana provisioning files) via write operations. The agent MUST NEVER execute `docker compose up`, `docker compose down`, `docker run`, or any other Docker/container-lifecycle command — not even with the user's implicit blessing, not even to "save the user a step." Starting, stopping, or otherwise managing the Docker daemon is exclusively the user's manual action. If asked to run it anyway, the agent must decline and point the user to the exact command to run themselves (§6 below).

This is an **entirely opt-in observability channel**, never a blocking gate anywhere in the lifecycle — see `skills/smoke-and-sanity-validation/SKILL.md` and `skills/bottleneck-root-cause-analysis/SKILL.md` for how VERIFY/AUDIT optionally add a k6 output flag when this stack is already running. The raw CLI log (`{strategy}-verify.log`/`{strategy}-audit.log`) remains the one and only evidence source the `bottleneck-auditor` Sub-Agent inspects — nothing in Prometheus/Grafana is ever added to a Sub-Agent audit payload.

## 1. Architecture

k6 runs directly on the host (not containerized) and remote-writes its metrics to the Prometheus container over `http://localhost:9090/api/v1/write`. The Grafana container queries Prometheus via PromQL over the Docker Compose network the two containers share. This keeps k6 itself outside Docker — no change to how the Master Agent invokes `k6 run` today, only an additional `--out` flag and an additional metrics destination.

```text
┌─────────────┐   remote-write    ┌──────────────┐   PromQL query   ┌───────────┐
│  k6 (host)   │ ───────────────▶ │  Prometheus   │ ◀─────────────── │  Grafana   │
│  k6 run ...  │  :9090/api/v1/   │  (container)  │                  │ (container)│
└─────────────┘      write        └──────────────┘                  └───────────┘
                                     :9090 (host)                       :3000 (host)
```

## 2. Complete `docker-compose.yml` Template

Persisted to `perf-test/observability/docker-compose.yml`. Docker Compose v3.8 syntax; two services, one shared network, both ports published to the host so the user can reach Grafana's UI and Prometheus's own UI/API directly.

```yaml
version: "3.8"

services:
  prometheus:
    image: prom/prometheus:v2.53.0
    container_name: perf-test-prometheus
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--web.enable-remote-write-receiver"
    # --web.enable-remote-write-receiver is REQUIRED: Prometheus ships with remote-write
    # ingestion disabled by default. Without this flag, k6's --out experimental-prometheus-rw
    # writes will be rejected even though every other part of this stack is configured correctly.
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    networks:
      - perf-test-observability

  grafana:
    image: grafana/grafana:11.1.0
    container_name: perf-test-grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
    depends_on:
      - prometheus
    networks:
      - perf-test-observability

networks:
  perf-test-observability:
    driver: bridge
```

## 3. `prometheus.yml`

Persisted to `perf-test/observability/prometheus/prometheus.yml`. k6 metrics arrive via remote-write, not via a scrape target — the only scrape job needed is Prometheus scraping its own `/metrics` endpoint (useful for confirming the container itself is healthy, not for k6 data):

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
```

## 4. Grafana Datasource Provisioning

Persisted to `perf-test/observability/grafana/provisioning/datasources/prometheus.yml`. This auto-registers Prometheus as a Grafana datasource on container start — the user never has to configure a datasource by hand in the UI:

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
```

Note `url: http://prometheus:9090` uses the Docker Compose service name (`prometheus`), not `localhost` — Grafana resolves this via the shared `perf-test-observability` network, distinct from the `localhost:9090` k6 uses from the host in §5.

## 5. Exact k6 Command

When the user confirms the stack is running, append this flag/tag to whichever `k6 run` command VERIFY/AUDIT would otherwise execute unchanged — see `skills/smoke-and-sanity-validation/SKILL.md` Step 2 and `skills/bottleneck-root-cause-analysis/SKILL.md` Step 2 for exactly where this substitution happens:

```bash
K6_PROMETHEUS_RW_SERVER_URL=http://localhost:9090/api/v1/write \
k6 run --out experimental-prometheus-rw --tag testid={strategy}-{phase}-{timestamp} perf-test/scripts/{strategy}.k6.js
```

- `{strategy}` — the strategy under test (e.g. `baseline`, `spike`).
- `{phase}` — `verify` or `audit`, matching whichever gate is invoking this command.
- `{timestamp}` — an ISO-8601-derived run identifier, so successive runs of the same strategy/phase remain distinguishable inside Grafana.

**This is an additional output, not a replacement.** `--out experimental-prometheus-rw` adds a metrics destination; it does not suppress k6's normal end-of-run summary text on stdout, which the Master must still capture in full into `perf-test/logs/{strategy}-{phase}.log` exactly as every other run today — the raw-log capture contract VERIFY/AUDIT already depend on is unchanged either way. **Before relying on this in production use, verify empirically with one real run that the terminal summary output is unaffected by the added `--out` flag — do not assume.**

## 6. Manual Steps for the User (never automated by the agent)

The agent's involvement stops at generating the three files in §2–§4. Everything below is printed for the user to run themselves — the agent never executes any of it:

1. `cd perf-test/observability && docker compose up -d`
2. Open `http://localhost:3000` in a browser (Grafana default login: `admin` / `admin`).
3. In Grafana: **New → Import**, enter dashboard ID `19665` (the official "k6 Prometheus" dashboard, maintained by Grafana Labs), select the pre-provisioned **Prometheus** datasource, click **Import**.
   - This dashboard is intentionally **not** auto-imported/embedded as a JSON file in this suite — ID `19665` is maintained externally by Grafana Labs, is fairly large, and can change independently of this repo. Pointing the user at the ID keeps this suite from shipping a copy of someone else's dashboard that can silently go stale; importing it is one extra click, not a meaningful burden.
4. Run the k6 command from §5.

## 7. Cleanup

`docker compose down` (run from `perf-test/observability/`) stops and removes the containers when the engagement is finished. Like every other step in §6, this is exclusively a manual action for the user to run themselves — the agent only ever generates the files, never manages the container lifecycle at any point, start or stop.
