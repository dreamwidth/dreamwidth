# dwtool

A terminal UI for managing Dreamwidth's ECS infrastructure. Replaces bouncing between the GitHub Actions UI, AWS Console, and CLI with a single tool.

## Features

- **Dashboard** — all ~42 ECS services grouped by Web, Workers (by category), and Proxy
- **Deploy** — pick a GHCR image, confirm, trigger the GitHub Actions deploy workflow, track progress
- **Service Detail** — view running tasks, status, and metadata
- **Logs** — stream CloudWatch logs with follow mode and search
- **Shell** — ECS Exec into a running container (suspends TUI, resumes on exit)
- **Filter** — search services by name with `/`

## Prerequisites

- Go 1.23+
- AWS credentials configured (env vars, `~/.aws/credentials`, or SSO)
- [`gh` CLI](https://cli.github.com/) authenticated (`gh auth login`) — used for deploys
- [`session-manager-plugin`](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) — required for shell access

## Build

```bash
cd src/dwtool
go build -o dwtool .
```

## Usage

Run with no arguments for the interactive TUI:

```bash
./dwtool
```

TUI flags:

| Flag | Default | Description |
|------|---------|-------------|
| `--region` | `us-east-1` | AWS region |
| `--cluster` | `dreamwidth` | ECS cluster name |
| `--repo` | `dreamwidth/dreamwidth` | GitHub repository |

### Headless commands

For scripting (and so Claude can drive it from the CLI), the same data is
available as non-interactive subcommands. Each prints human-readable text by
default, machine-readable JSON with `--json`, and sets a non-zero exit code on
failure. All accept `--region` and `--cluster`.

| Command | Description |
|---------|-------------|
| `dwtool services [--group web\|worker\|proxy] [--filter X] [--no-images] [--json]` | List ECS services and their rollout state |
| `dwtool status <service> [--json]` | One service's deployments and running tasks |
| `dwtool images <service> [--target worker22] [--limit N] [--json]` | Deployable GHCR images, newest first (`*` = currently deployed) |
| `dwtool log-scan -keyword <term> [...]` | Search logs across services via Loki |
| `dwtool esn-trace <trace-id-or-url> [...]` | Trace an ESN event through the pipeline |

`services`/`status`/`images` need AWS credentials; `images` additionally needs
the `gh` CLI authenticated. `log-scan`/`esn-trace` use Loki credentials from
`~/.config/dwtool/config.json` or `DWTOOL_LOKI_*` env vars. Run
`dwtool <command> --help` for the full flag list.

```bash
dwtool services --group web --json
dwtool status web-stable-service
dwtool images worker-esn-process-sub-service --target worker22
```

## Keybindings

| Key | Action |
|-----|--------|
| `j` / `k` | Move cursor |
| `Enter` | Service detail |
| `d` | Deploy service |
| `D` | Deploy all workers |
| `l` | View logs |
| `s` | Shell into container |
| `/` | Filter services |
| `r` | Refresh |
| `?` | Help |
| `Esc` | Back |
| `q` | Quit |

## Stack

Go + [Bubble Tea](https://github.com/charmbracelet/bubbletea) v1 + [Lipgloss](https://github.com/charmbracelet/lipgloss) v1 + [aws-sdk-go-v2](https://github.com/aws/aws-sdk-go-v2)
