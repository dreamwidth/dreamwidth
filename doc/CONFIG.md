# Dreamwidth Configuration Management

This document describes how Dreamwidth's Perl configuration is structured, how it
is loaded, and how running web and worker processes pick up changes. This is the
behavior of **`cgi-bin/LJ/Config.pm`** and is true for any deployment. How the
config *files* are physically stored and delivered to processes (bind mount, baked
into an image, shared filesystem, config-management tool) is deployment-specific
and out of scope here.

## Files and load order

`LJ::Config` loads these files, in this order (`cgi-bin/LJ/Config.pm:26-60`):

| Order | File | Purpose |
|-------|------|---------|
| 1 | `etc/config-private.pl` | Private, site-specific settings and **secrets** (DB creds, API keys, `%DBINFO`, `@CLUSTERS`). |
| 2 | `etc/config-local.pl` | Site-local, non-secret overrides. |
| 3 | `etc/config.pl` | Public defaults. |
| 4 | `cgi-bin/LJ/Global/Defaults.pm` | Hardcoded fallback defaults. |

**Earlier files win.** Files later in the chain are written to "not clobber"
anything already set, so `config-private.pl` overrides `config-local.pl`, which
overrides `config.pl`, which overrides `Global/Defaults.pm`. Put your overrides in
`config-private.pl` or `config-local.pl` — **do not edit `config.pl`** for a
deployment.

Only the `*.example` templates are tracked in git (`etc/config.pl.example`,
`etc/config-private.pl.example`, `etc/config-local.pl.example`). The real
`config-private.pl` / `config-local.pl` are deployment-local and git-ignored. The
example files are the canonical schema — when adding a new knob, document it there.

`$LJ::HOME` (from `$ENV{LJHOME}`, `Config.pm:22`) locates the `etc/` directory.
Config can also be overlaid via `$LJHOME/ext/*` scopes (`LJ::resolve_file`,
`cgi-bin/LJ/Directories.pm:50-89`).

## How processes load config

Initial load happens once at process start: `cgi-bin/ljlib.pl:47` calls
`LJ::Config->load`, which `do`'s each file in the list (`Config.pm:87-93`).
`load` is idempotent (guarded by `$LJ::CONFIG_LOADED`).

## Live reload

Running processes pick up config edits **without a restart**, via an mtime watcher:

- **Sub:** `LJ::Config::start_request_reload` (`cgi-bin/LJ/Config.pm:96-142`).
- **Trigger:** called once per request/job from `LJ::start_request`
  (`cgi-bin/ljlib.pl:498-499`).
- **Throttle:** it only `stat()`s the config files if more than **10 seconds**
  have passed since the last check (hardcoded, `Config.pm:101-102`).
- **Detection:** it takes the newest mtime across *all* config files; if that is
  newer than the last-seen mtime, it reloads.
- **Reload action:** `LJ::Config::reload` (`Config.pm:73-84`) re-`do`'s every
  config file into the existing `%LJ::` symbol table, then re-applies dependent
  state (DB sources via `$LJ::DBIRole->set_sources`, `LJ::MemCache::reload_conf`,
  prefix snapshots, `$LJ::LOCKER_OBJ`).

This applies to **both web and workers**, because both funnel through
`LJ::start_request`:

- **Web (Starman/Plack):** every HTTP request (`ljlib.pl:469`).
- **SQS task workers:** `DW::TaskQueue::start_work` calls `LJ::start_request` per
  message (`cgi-bin/DW/TaskQueue.pm:216`), so each job gets the same reload check.
- **Standalone/loop workers** (e.g. `bin/worker/paidstatus`) call
  `LJ::start_request` in their own loops too.

So an edit to a config file is picked up by every process that reads it within
~10 seconds — subject to the caveat below.

### Reload caveat: removals need a restart

Reload re-executes the files into the *existing* symbol table; it does not wipe
globals first. So **removing or renaming** a config variable does not unset it on
running processes — the old value persists until the process restarts. Value
changes take effect live; removals and renames require a restart.

## Startup validation and failure behavior

The live-reload path and the startup path treat a broken config **differently** —
this asymmetry is the main hazard when editing config.

- **Live reload does not validate and does not crash.** `load_config` uses a bare
  `do $fn` with no `$@` check (`Config.pm:89`). A Perl syntax error there makes
  `do` return `undef` without dying, so the file's new contents are silently
  skipped and the process keeps its last-good values for that file (reloading the
  others). Already-running processes therefore *appear* fine.
- **Startup validates and refuses to serve.** The provided container entrypoints
  (`etc/docker/{web22,worker22}/scripts/startup-prod.sh`) run `bin/checkconfig.pl`
  first, which `perl -c`'s each config file and dies on failure. On failure the
  web entrypoint hangs (`sleep infinity`, so the task is up but never serves) and
  the worker entrypoint exits after a short delay (crash-loop with backoff).

The trap: a syntax-broken config can leave **already-running processes looking
healthy while any newly started or recycled process fails to come up** — and
Starman recycles each worker after a bounded number of requests
(`--max-requests`), so new workers replace old ones continuously. Do not treat
"it's still running" as proof the config is valid.

## Changing config safely

Because the file is mtime-watched and read live, and because the live-reload path
performs no validation, the file that processes read must **never transiently
contain unvalidated content**. Regardless of how your deployment stores config,
the safe pattern is:

1. **Back up** the current file.
2. **Write the edit to a new/temporary file**, not the live file.
3. **Validate** it before it goes live — `perl -c` the new file (also `perl -c`
   the current file first, so you know the check is meaningful), or run
   `bin/checkconfig.pl`. Use the deployment's Perl and `@INC` (set `LJHOME` and the
   `extlib` path). Confirm the diff is exactly the intended change.
4. **Atomically replace** the live file (a `rename(2)` on the same filesystem is
   atomic and preserves permissions). The mtime bump triggers reload within ~10s.
5. **Verify** the change took effect behaviorally.
6. **To revert:** atomically move the backup back.

Prefer `config-private.pl` / `config-local.pl` for overrides; never hand-edit
`config.pl`. Remember that a **removal or rename** additionally needs a restart
(see [Reload caveat](#reload-caveat-removals-need-a-restart)).
