# Project guidance

Dreamwidth is a Perl journaling platform forked from LiveJournal. It runs on
Plack/Starman with MySQL, Memcached, and background job queues. Follow `LICENSE`
and the applicable file headers: Dreamwidth-authored files generally use the same
terms as Perl itself, while LiveJournal-derived files retain their inherited
terms. `ext/dw-nonfree/` has separate restrictions. Preserve copyright and license
notices; see `CONTRIBUTING.md` for contributor requirements.

## Development environment

Edit code and run Git on the host. Run tests, formatting, and builds inside the
devcontainer; worktree Git metadata may not resolve inside the container.
The repository is mounted at `/workspaces/dreamwidth` (`$LJHOME`), with Perl
dependencies at `/opt/dreamwidth-extlib/lib/perl5` (`$PERL5LIB`).

Ensure Docker is running (start Docker Desktop on macOS or Windows), then run
these commands from the checkout root on the host:

```bash
npx @devcontainers/cli up --workspace-folder .
docker ps --filter "label=devcontainer.local_folder=$(pwd)" --format '{{.ID}}'
docker exec -w /workspaces/dreamwidth <container-id> <command>
docker port <container-id>
```

Use `docker exec -it <container-id> bash` for an interactive shell; omit `-it`
for automated commands. Host ports are assigned dynamically.

Use separate Git worktrees and devcontainers for concurrent work. Do not change
another session's checkout or container. Each worktree mounts at the same
container path and gets a MySQL volume named for its folder, so use distinct
folder names. The setup script creates the `extlib/` symlink automatically.

## Commands and validation

Run these from `$LJHOME` inside the devcontainer:

```bash
perl t/sometest.t                 # Run an individual test
perl extlib/bin/tidyall -a        # Apply formatting
perl t/02-tidy.t                  # Check formatting
perl t/00-compile.t               # Check all modules compile
bin/build-static.sh              # Build CSS and JavaScript
```

For visual verification of page or template changes, use `bin/dev/screenshot`.
See `doc/SCREENSHOTS.md` for setup, authenticated pages, and copying images out
of the container.

Before pushing code changes, apply formatting and run the formatting and compile
checks above. Also run tests covering the changed behavior. CI runs only part of
the suite; consult `.github/workflows/ci.yml` for its current coverage rather
than treating a green CI run as complete validation.

Restart the dev web server after configuration or startup changes:

```bash
pkill starman; bash .devcontainer/start.sh
```

## Code conventions and architecture

- Formatting is defined in `.tidyallrc`: Unix line endings, 4-space continuation
  indentation, and a 100-character line limit for the selected Perl files.
- New files must use the full Dreamwidth header: filename/module description,
  `Authors:` block, copyright year and `Dreamwidth Studios, LLC.`, followed by
  the standard Perl license paragraph. Copy an appropriate neighboring header;
  do not abbreviate the license notice.
- Comments should explain non-obvious constraints or ordering requirements.
  Change history belongs in commit messages.
- `DW::*` contains modern Dreamwidth code; `LJ::*` contains legacy code that
  remains core to users, entries, and comments; `S2::*` implements the style and
  theming compiler.
- Requests flow through `cgi-bin/Plack/Middleware/DW/`, `DW::Routing`,
  `DW::Controller::*`, and `DW::Template`. Template Toolkit views live in
  `views/`; legacy BML pages live in `htdocs/`. See `doc/PLACK.md`.
- In devcontainers, `LJ::Global::Defaults` intentionally sets `$LJ::DOMAIN`,
  `$LJ::SITEROOT`, and related globals to empty strings so URLs use the request
  Host header. Do not override these with `local` in middleware: the override
  affects downstream code.

## Pull requests

Target `dreamwidth/dreamwidth`. When opening a PR from a fork, use
`--head <fork-owner>:<branch-name>`; inspect the remote to identify the fork owner.
Follow the repository's existing commit message style.

Keep review screenshots out of Git; attach them to the PR instead. Put feature
flow explanations and rollout notes in the PR description rather than adding
standalone feature documents to `doc/`.

Keep PR bodies short, with a technical description of the mechanism and key
files, followed by a required plain-language CODE TOUR for the community:

```text
<A few sentences explaining what changed and why.>

CODE TOUR: <One short paragraph describing the user-visible change.>

Fixes #<issue-number>
```

Omit the `Fixes` line when there is no linked issue.
