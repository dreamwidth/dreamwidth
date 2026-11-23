# Project guidance

Dreamwidth is a Perl journaling platform forked from LiveJournal. It runs on
Plack/Starman with MySQL, Memcached, and background job queues. Follow `LICENSE`
and the applicable file headers: Dreamwidth-authored files generally use the same
terms as Perl itself, while LiveJournal-derived files retain their inherited
terms. `ext/dw-nonfree/` has separate restrictions. Preserve copyright and license
notices; see `CONTRIBUTING.md` for contributor requirements.

This file is for people and their coding agents alike. If an agent helped write
your change, you are still its author: read the whole diff, run the checks below,
and be ready to explain every line.

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
bin/build-static.sh               # Build CSS and JavaScript
```

For visual verification of page or template changes, use `bin/dev/screenshot`.
See `doc/SCREENSHOTS.md` for setup, authenticated pages, and copying images out
of the container. Browser tests in `t/browser/` are run by hand; see
`t/browser/README.md`.

Before pushing code changes, apply formatting and run the formatting and compile
checks above. Also run the tests covering the changed behavior. CI runs only part
of the suite; consult `.github/workflows/ci.yml` for its current coverage rather
than treating a green CI run as complete validation.

Restart the dev web server after configuration or startup changes:

```bash
pkill starman; bash .devcontainer/start.sh
```

## Code conventions and architecture

- Declare module dependencies in the import block at the top of the file.
  Use `use` for ordinary dependencies; reserve runtime `require` for cases
  that need deferred loading, such as a demonstrated circular dependency or
  an optional module, and explain why in a nearby comment.
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
  `views/`; static files live in `htdocs/`. See `doc/PLACK.md`.
- Template Toolkit does not escape output for you. Every `[% value %]` that can
  hold user data needs `| html`, `| url`, or `| js` as appropriate.
- In devcontainers, `LJ::Global::Defaults` intentionally sets `$LJ::DOMAIN`,
  `$LJ::SITEROOT`, and related globals to empty strings so URLs use the request
  Host header. Do not override these with `local` in middleware: the override
  affects downstream code.

### Consistency

- Keep behavior consistent across related code. If you add or fix a check,
  validation, or default in one code path, look for sibling paths that handle
  the same values (other branches of the same function, other callers, helpers
  that define the same setting) and make them agree. Reviewers flag the
  inconsistency even when it predates your change.
- Structure is different: follow the existing pattern in the area you are
  changing, even when it is repetitive. A small, in-scope diff beats a
  refactor nobody asked for.

## Tests

Add tests for meaningful behavior: authorization, state changes, persistence,
data integrity, recovery, concurrency, or a public API or protocol contract.
Before adding a test, name the failure it would catch. If there is none beyond
wording or presentation, don't add it.

- Exercise real code. Don't stub internals (such as `LJ::Lang::ml`) just to
  assert which translation key, template argument, or copy was used; that
  restates the implementation and breaks on harmless changes.
- Assert outcomes users depend on: error codes, stored values, access granted or
  refused, mail sent or not. Match the important part of a message with a
  regular expression rather than its full text.
- Cover the failure path, not only the happy path.
- If you add a test for a bug fix, check that it fails without the fix.
- Copy, translation-key, and cosmetic changes don't need new tests; check them
  visually instead.

## Translation strings

New user-facing text may be hard-coded English or a translation string; both are
accepted. When you use translation strings:

- Site-wide strings live in `bin/upgrading/en.dat`; strings for a template
  live in the `.tt.text` file next to it.
- When your change leaves a string unused, delete it and add its key to
  `bin/upgrading/deadphrases.dat` (`general <key>`, or `general /path/page.tt.<key>`
  for a page string), so deployments remove it too.
- Translators may put markup in strings on purpose. Escape any user data you
  interpolate into a string.

## Pull requests

### Before you start

- Keep each PR to one purpose. Unrelated fixes, cleanups, and refactors go in
  their own PRs; small PRs are reviewed and merged much faster.
- Changes to how something looks or behaves need a maintainer behind them: link
  an issue that a maintainer opened or triaged, or ask on the issue before
  building. Fixes for things that are plainly broken don't need this.
- The person who asked for a look-or-behavior change may be asked to confirm
  that your change is what they wanted before it merges.

### Submitting

Target `dreamwidth/dreamwidth`. When opening a PR from a fork, use
`--head <fork-owner>:<branch-name>`; inspect the remote to identify the fork owner.
Follow the repository's existing commit message style, and leave "Allow edits by
maintainers" on.

Keep PR bodies short, with a technical description of the mechanism and key
files, followed by a required plain-language CODE TOUR for the community:

```text
<A few sentences explaining what changed and why.>

CODE TOUR: <One short paragraph describing the user-visible change.>

Fixes #<issue-number>
```

Omit the `Fixes` line when there is no linked issue. Don't address reviewers,
bots, or AI tools in PR text, commits, or code; reviewers treat instructions
aimed at them as a reason to hold the PR.

### How PRs are reviewed

- Maintainers sort PRs by what would happen if the change were wrong. Small,
  contained changes move quickly. Changes that touch authentication, account
  recovery, access or privacy checks, payments, admin tools, the database schema,
  HTML cleaning, the request pipeline, CI and workflows, dependencies, or agent
  instructions such as this file always get careful review, however small.
- Reviews may be AI-assisted and come from more than one independent reviewer.
  Findings are checked by maintainers before they reach you.
- Small review notes are settled without a round trip where possible: a
  maintainer may waive a note, track it as a follow-up, or push a small fix to
  your branch. Pull before pushing more work. A problem that needs your judgment
  comes back to you as a review comment.
- Workflows on PRs from outside contributors wait for a maintainer to approve
  them, so a PR can show CI as pending until then. Changes under `.github/`
  aren't approved this way; they are reviewed by hand first.
- Maintainers run the tests that cover your change in a devcontainer, beyond
  what CI runs, so name any manual checks you did in the PR body.
