# Dreamwidth Plack Implementation

This document describes the Plack/Starman web server implementation for Dreamwidth, including architecture, middleware, routing, and testing.

## Overview

Dreamwidth runs under both Apache/mod_perl and Plack/Starman. The `DW::Request` abstraction layer lets most application code work under either server. The Plack stack handles routing, BML rendering, journal pages, static assets, authentication, and sysban enforcement.

## Running the Server

```bash
# Inside the devcontainer
perl bin/starman --port 8080              # single worker (default)
perl bin/starman --port 8080 --workers 4  # multi-worker
```

The entry point is `app.psgi`. The `LJ_IS_DEV_SERVER` environment variable enables dev mode (hot-reloading, `?as=` impersonation, auto-verified accounts). See the safety warning in `cgi-bin/ljlib.pl`.

## Middleware Stack

Applied in order by `app.psgi` via `Plack::Builder`. Order matters.

| Order | Middleware | File | Purpose |
|-------|-----------|------|---------|
| 1 | `Plack::Middleware::Options` | (CPAN) | Handles OPTIONS requests; rejects disallowed HTTP methods |
| 2 | `DW::RequestWrapper` | `Plack/Middleware/DW/RequestWrapper.pm` | Creates `DW::Request::Plack`, calls `LJ::start_request()`/`end_request()`, registers standard resources |
| 3 | `DW::Redirects` | `Plack/Middleware/DW/Redirects.pm` | Canonical domain redirects and `redirect.dat` entries |
| 4 | `DW::Dev` | `Plack/Middleware/DW/Dev.pm` | Dev-only: hot-reloads changed Perl modules |
| 5 | `DW::XForwardedFor` | `Plack/Middleware/DW/XForwardedFor.pm` | Extracts real client IP from X-Forwarded-For when `$TRUST_X_HEADERS` is set |
| 6 | `DW::ConcatRes` | `Plack/Middleware/DW/ConcatRes.pm` | Concatenated CSS/JS combo handler (`/stc/??a.css,b.css`) |
| 7 | `Plack::Middleware::Static` | (CPAN) | Serves static files from `htdocs/` directories (`/img/`, `/stc/`, `/js/`) |
| 8 | `DW::UniqCookie` | `Plack/Middleware/DW/UniqCookie.pm` | Ensures unique tracking cookie is set |
| 9 | `DW::Auth` | `Plack/Middleware/DW/Auth.pm` | Resolves session cookies, sets remote user. Dev: `?as=username` impersonation |
| 10 | `DW::Sysban` | `Plack/Middleware/DW/Sysban.pm` | Checks IP/uniq/tempbans, returns 403 for banned requests |

## Request Routing

The `$app` handler in `app.psgi` dispatches requests through three systems in order:

1. **DW::Routing** — Modern controller-based routes (`DW::Controller::*`). Handles `/api/v\d+/` endpoints and all routes registered via `DW::Routing->register_*`.

2. **DW::Controller::Journal** — Path-based journal URLs (`/~user/...`, `/users/user/...`). Extracts the journal username and delegates to `LJ::make_journal()`.

3. **DW::BML** — Legacy BML page fallback. Resolves URI to a `.bml` file in `htdocs/`, renders it via the BML engine (shared with `Apache::BML`).

If none of these handle the request, a 404 is returned.

## Key Modules

### DW::Request::Plack (`cgi-bin/DW/Request/Plack.pm`)

Implements the `DW::Request` interface over `Plack::Request`/`Plack::Response`. Provides `method()`, `uri()`, `path()`, `host()`, `header_in()`, `header_out()`, `status()`, `print()`, `redirect()`, `res()`, and cookie management. `uri()` returns path-only (not full URL) to match Apache behavior.

### DW::BML (`cgi-bin/DW/BML.pm`)

Plack-compatible BML renderer. Reuses the core BML engine from `Apache::BML` (`%Apache::BML::FileConfig`) while replacing the Apache-specific request handling. Includes path traversal protection and `_config.bml` access blocking.

### DW::Controller::Journal (`cgi-bin/DW/Controller/Journal.pm`)

Shared journal rendering controller. Validates usernames via `LJ::canonical_username()`, delegates access control and rendering to `LJ::make_journal()`. Handles entry date validation against URL parameters.

### DW::Controller::Userpic (`cgi-bin/DW/Controller/Userpic.pm`)

Serves userpic images. Route regex ensures numeric IDs only. Works under both Apache and Plack.

## Testing

### Test Files

| Test | What it covers |
|------|---------------|
| `t/plack-app.t` | Module loading, `app.psgi` compilation, request/response object methods, API route detection |
| `t/plack-middleware.t` | Middleware module loading, instantiation, inheritance |
| `t/plack-auth.t` | Auth middleware: session resolution, `?as=` impersonation, anonymous handling |
| `t/plack-sysban.t` | Sysban middleware: IP bans, uniq bans, tempbans, noanon_ip |
| `t/plack-integration.t` | Full middleware stack: homepage rendering, API endpoints, redirects, method filtering |
| `t/plack-static.t` | Static file serving from htdocs directories |
| `t/plack-bml.t` | BML page resolution and rendering |
| `t/plack-controller.t` | Journal controller routing and rendering |

### Running Tests

```bash
# All Plack tests
prove t/plack-*.t

# Individual test
prove -v t/plack-auth.t
```

Tests use mocking (`LJ::Session`, `LJ::load_user`, `DW::Routing::call`, etc.) to run without a full database. Most tests load the real `app.psgi` and exercise the full middleware stack via `Plack::Test`.

## Security Notes

- `LJ_IS_DEV_SERVER` must never be set in production. It enables `?as=` user impersonation, auto-verified accounts, and skips domain validation. See comment in `cgi-bin/ljlib.pl`.
- Auth middleware always marks auth resolution (calls `set_remote` even for anonymous) to prevent `LJ::get_remote()` from re-entering session resolution.
- Sysban middleware checks `LJ::get_remote_ip()` plus all X-Forwarded-For IPs, matching the Apache `@req_hosts` pattern.
- XForwardedFor only processes proxy headers when `$LJ::TRUST_X_HEADERS` is configured.

## Adding New Middleware

1. Create module in `cgi-bin/Plack/Middleware/DW/`, inheriting from `Plack::Middleware`
2. Add `enable` line in `app.psgi` at the appropriate position in the stack
3. Add tests in `t/plack-*.t`
4. Run `perl extlib/bin/tidyall <file>` and `prove t/plack-*.t`
