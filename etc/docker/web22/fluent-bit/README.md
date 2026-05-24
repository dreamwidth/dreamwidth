# web22 Fluent Bit configs

Source-of-truth copies of the Fluent Bit sidecar (`log_router`) configs used by
the web22 ECS tasks. These are **delivered via EFS**, not by the application
image — the operator copies them onto the per-class EFS roots:

| Repo file     | EFS destination                       | Used by                       |
|---------------|---------------------------------------|-------------------------------|
| `canary.conf` | `/etc-canary/fluent-bit/web.conf`     | web-canary (error + access)   |
| `parsers.conf`| `/etc-canary/fluent-bit/parsers.conf` | web-canary (access JSON parse)|
| `stable.conf` | `/etc-stable/fluent-bit/web.conf`     | web-shop, web-unauthenticated (error only) |

Inside the container the `dw-config` EFS volume is mounted at `/dw/etc`, so the
sidecar runs `fluent-bit -c /dw/etc/fluent-bit/web.conf`.

`${LOKI_USER}` / `${LOKI_PASSWORD}` come from the task's ECS `secrets` (the
shared Grafana Cloud SSM params). `${DW_LOKI_SERVICE}` is set per service in the
task def `environment` and becomes the Loki `service` label, so the shared
`stable.conf` labels shop vs. unauthenticated correctly.

Validate locally (on a host with Docker) with `fluent-bit ... --dry-run`; see
`docs/superpowers/plans/2026-05-24-web22-loki-logging.md`.
