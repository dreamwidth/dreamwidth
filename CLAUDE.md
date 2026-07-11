# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dreamwidth is a Perl-based journaling/blogging platform forked from LiveJournal. It runs on Plack/Starman with MySQL, Memcached, and background job queues. All code must be GPL-licensed.

## Development Environment

Code is edited on the host. **Run git on the host** — a worktree's `.git` doesn't resolve inside the container, so `git` commands there fail. **Run everything else inside the devcontainer** (`.devcontainer/`): tests, tidy, builds. The devcontainer runs Ubuntu 22.04 with MySQL, Memcached, and a Plack/Starman web server; the workspace is mounted at `/workspaces/dreamwidth` (`$LJHOME`), and Perl modules are pre-installed at `/opt/dreamwidth-extlib/lib/perl5` (`$PERL5LIB`).

### Container Management

Build and start the devcontainer from the repo root:

```bash
npx @devcontainers/cli up --workspace-folder .
```

Find the running container ID for your workspace:

```bash
# Filter by your workspace path to avoid grabbing another session's container
docker ps --filter label=devcontainer.local_folder=$(pwd) --format "{{.ID}}"

# Or list all devcontainers
docker ps --format "{{.ID}} {{.Names}}"
```

Run commands inside the container (omit `-it` when not in a TTY, e.g. from Claude Code):

```bash
# Interactive shell
docker exec -it <container-id> bash

# Non-interactive command execution (use this from Claude Code)
docker exec <container-id> <command>
```

### Commands (run inside devcontainer)

```bash
# Run a single test
perl t/sometest.t

# Check code formatting (must pass before PR)
perl t/02-tidy.t

# Apply code formatting
perl extlib/bin/tidyall -a

# Check all modules compile
perl t/00-compile.t

# Compile static assets (CSS/JS)
bin/build-static.sh

# Restart the dev web server after code changes (the dev Starman hot-reloads
# changed modules via DW::Dev; restart for config/startup changes)
pkill starman; bash .devcontainer/start.sh
```

### Worktree Workflow (ALWAYS work in a worktree)

**ABSOLUTE RULE — You MUST ALWAYS work in a git worktree. NEVER do work directly in the main checkout (`/home/mark/dreamwidth`).** This is not optional and is not only for "parallel work". Multiple Claude instances and the user share the main checkout; doing anything there — editing files, `git checkout`/`gh pr checkout` to switch its branch, running builds — stomps on whatever else is using it and corrupts their state. The main checkout must be left on `main` and untouched.

The ONLY exceptions, each requiring EXPLICIT user instruction in that moment:
- The user explicitly tells you to work in the main directory.
- The user explicitly asks for a read-only action there (e.g. "what branch is main on?").

If you are not in a worktree, your FIRST action for any task that touches files, branches, or builds is to create one with `EnterWorktree`. If you ever find yourself about to edit, `checkout`, or build in the main checkout without explicit permission, STOP and create a worktree instead. The main checkout is shared territory; treat it as read-only by default.

Each worktree is an isolated git worktree with its own devcontainer, so many sessions can work simultaneously without stepping on each other.

**Create a worktree** using Claude Code's built-in `EnterWorktree` tool. This creates a worktree under `.claude/worktrees/<name>` and switches your session into it. (Reviewing a PR? Create a worktree and `gh pr checkout` *inside it* — never in the main checkout.)

**Start a devcontainer for the worktree:**

```bash
npx @devcontainers/cli up --workspace-folder <worktree-path>
```

This works because `devcontainer.json` uses `workspaceMount` to always mount at `/workspaces/dreamwidth` (matching `$LJHOME`) regardless of the host folder name, and each worktree gets its own MySQL volume (`dreamwidth-mysql-<foldername>`).

**Find your container** (filter by the worktree label to avoid grabbing someone else's):

```bash
docker ps --filter label=devcontainer.local_folder=<worktree-path> --format "{{.ID}}"
```

**Port isolation:** All devcontainers use dynamic host ports (container ports 8080/8081 are mapped to random available host ports). Use `docker port <container-id>` to find the assigned ports.

**Important rules:**
- NEVER work in, edit, switch the branch of, or build in the main checkout (`/home/mark/dreamwidth`) without explicit per-task permission — always use a worktree (see the ABSOLUTE RULE above). Leave the main checkout on `main`.
- Never touch another session's worktree or its devcontainer
- Each worktree gets its own devcontainer — never share containers between worktrees
- The `extlib/` symlink is created automatically by `setup.sh` (points to `/opt/dreamwidth-extlib` in the image)
- All the same commands work: `perl extlib/bin/tidyall -a`, `perl t/02-tidy.t`, `perl t/00-compile.t`

## Code Formatting

Enforced via Perl::Tidy (`.tidyallrc`): Unix line endings, 4-space continuation indent, 100-char line limit. Applies to `bin/`, `cgi-bin/`, `t/`, and worker scripts. Run `bin/tidyall` to auto-format; `t/02-tidy.t` validates in CI.

**Comments:** comment the non-obvious constraint the code can't show on its own — an invariant, a why-this-order, a footgun. Never narrate the change ("was X, now Y") — that belongs in the commit message, not the code. One line unless it's a genuine gotcha.

## Architecture

- **`DW::*`** — modern Dreamwidth code (controllers, auth, storage, templates). **`LJ::*`** — legacy LiveJournal modules, still core to users/entries/comments. **`S2::*`** — the S2 style/theming compiler.
- Request pipeline: Plack middleware (`cgi-bin/Plack/Middleware/DW/`) → `DW::Routing` → `DW::Controller::*` → `DW::Template` (`.tt` views in `views/`). Legacy pages use BML in `htdocs/`. See **`doc/PLACK.md`** for the full architecture.
- Config: `etc/config-private.pl` → `config-local.pl` → `config.pl` → `LJ::Global::Defaults` (earlier wins), loaded by `LJ::Config`. Running web and workers live-reload on mtime change (~10s, `LJ::Config::start_request_reload`) with no restart — but the reload path doesn't validate, so a syntax error silently no-ops on running procs while `checkconfig.pl` crash-loops any new/recycled one. See **`doc/CONFIG.md`** for the load/reload model and the safe-edit procedure.
- **Dev-container globals (gotcha):** the dev container (`$IS_DEV_SERVER && $IS_DEV_CONTAINER`) intentionally sets `$LJ::DOMAIN`, `$LJ::SITEROOT`, etc. to `""` in `LJ::Global::Defaults`, so URLs are built from the request Host header. Do **not** use `local` to override these in middleware — it leaks into downstream code.

## Git Workflow

**ABSOLUTE RULE — NEVER run `git commit` unless the user has explicitly asked you to commit in that moment.** Not after making changes. Not as part of a workflow. Not proactively. Not because the changes look ready. Not for any reason whatsoever. The ONLY acceptable trigger is the user saying words like "commit this" or "go ahead and commit". If in doubt, ASK. Violating this rule destroys trust. Follow the repository's existing commit message style. **NEVER amend commits unless explicitly instructed** — assume commits have already been pushed.

Always use `--no-gpg-sign` when committing, as GPG signing requires interactive passphrase entry which hangs in this environment.

### Before Pushing

Before pushing any branch, run these inside the devcontainer and fix any failures — CI runs them and fails the build even for files you didn't touch:

1. `perl extlib/bin/tidyall -a` — auto-format all files
2. `perl t/02-tidy.t` — verify formatting passes
3. `perl t/00-compile.t` — verify all modules compile

CI runs only a **subset** of the suite (`02-tidy`, `00-compile`, `plack-*`, `cleaner-*`, `routing-*`, `rate-limit`), so a green CI does **not** mean your change is tested. Also run the test files your change touches (e.g. `t/search.t`, `t/rename.t`) locally — most of `t/` never runs in CI.

## Pull Requests

PRs target `dreamwidth/dreamwidth`. If the working repo is a fork, use `--head <fork-owner>:<branch-name>` (check the `origin` remote to determine the fork owner).

**Keep PR bodies short.** Both sections together should fit on one screen. The technical description is a few sentences naming the mechanism and the key files — not a restatement of the diff or a bullet list of every changed file. The CODE TOUR is one short paragraph in plain language. Reviewers read these on phones; verbosity is a tax.

Every PR must include a CODE TOUR. Omit `Fixes #N` when there's no linked issue.

PR body format:

```
<Technical description: what mechanism changed and why, naming the key files/functions.
For developers. A few sentences.>

CODE TOUR: <Non-technical description for the Dreamwidth community. What changed from a
user's perspective, no implementation. One short paragraph, conversational.>

Fixes #<issue-number>
```

## Troubleshooting

If the container startup fails (`postCreateCommand`), the container still exists. Check the error output, fix the issue, remove the container (`docker rm <id>`), and rebuild.
