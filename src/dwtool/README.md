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

```bash
./dwtool
```

Flags:

| Flag | Default | Description |
|------|---------|-------------|
| `--region` | `us-east-1` | AWS region |
| `--cluster` | `dreamwidth` | ECS cluster name |
| `--repo` | `dreamwidth/dreamwidth` | GitHub repository |

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
