# BML removal: resume handoff

## Start here

Read this file, [BML-PROGRESS.md](BML-PROGRESS.md),
[BML-REMOVAL-PLAN.md](BML-REMOVAL-PLAN.md), [BML-MIGRATION.md](BML-MIGRATION.md),
and the applicable AGENTS.md before work. The inventory in the plan is the
original baseline; the progress log records subsequent removals.

Checkpoint branch: `zorkian/dreamwidth:bml-overnight-20260921`.
Baseline: `d9ea4bea6`. Six completed work commits:

| Commit | Package |
|---|---|
| ee3db5005 | Inventory, removal plan, initial characterization |
| c2ed9b0f9 | Access-filter controller/template/JS migration |
| 0f6bf0fb7 | Shared widget request state and request-isolation fixes |
| 50276ed0a | Standalone image-preview iframe migration |
| d5c4037a8 | Standalone rich-text image dialog migration |
| 65e502439 | Customization HTTP/browser baseline and progress log |

13 BML page files remain, plus three configs, nine translation files, two looks,
and shared runtime dependencies. The entire BML system is NOT removed.
The previous agent stopped at a clean checkpoint despite instructions to
continue. That was not a blocker and must not become the stopping rule again.

## User instructions and current authorization

- Work toward removal of the entire BML system. Continue subsequent packages
  when prerequisites are satisfied. Keep reviewable commits and a progress log.
- Do not stop at a clean checkpoint, passing tests, or completion of one package.
  Once resumed, stop only when done or genuinely blocked across all available
  independent work. Document unresolved product decisions and continue elsewhere.
- Run required tests and headless browser checks. Use isolated worktrees and
  devcontainers. No deployment or production changes.
- User selected this Herdr session as an **Astra foreman**, **Terra** for
  implementation, and **Sol** for independent review; multiple agents are allowed.
  This architecture was planned but NO agents have been started and no Sol review
  has occurred. Do not describe these existing commits as independently reviewed.
- The latest task is to preserve/push this checkpoint and open a PR for visibility,
  rather than start the agent workflow now. Resume implementation when the user
  explicitly instructs the new window to do so. This push/PR is explicitly
  authorized; the earlier no-push restriction was superseded for this checkpoint.
- Questions and discussion are not implementation authorization. Respect any
  subsequent user instruction, especially stop/pause instructions.

## Foreman/implementation/review workflow on resume

Astra owns the inventory, dependency gates, acceptance criteria, integration,
review triage, and user updates. Start a Terra worker with a bounded package and
explicit preserved behavior/tests/deletion criteria. Sol reviews a fixed commit
ID independently for lost functionality, permissions, CSRF, compatibility,
request isolation and meaningful test coverage. Astra decides fixes and sends
concrete corrections back to Terra; Sol rechecks material fixes. Commit and
integrate validated results, update the ledger, and immediately take the next
unblocked package. Do not equate one blocked stream with overall blockage.

Use the explicit model overrides `gpt-5.6-terra` for implementers and
`gpt-5.6-sol` for reviewers; the supervising session should use `gpt-6-astra`.
Pass a self-contained task/handoff when starting agents with limited context.
With four total slots, use Astra + up to two independent Terra workers + Sol.
Separate implementation worktrees/containers; no agents write to the same checkout.
Review fixed commits in a separate review checkout when running tests. Do not
invent Herdr window-control capabilities: use available agents/worktrees and
report any orchestration limitation honestly.

## Immediate next package

Customization migration, detailed in the progress log:

1. Make widget JS/resources compatible with Foundation resource ordering and
   initialization, including nested widgets and AJAX refresh. Legacy widgets use
   DOM-style `$`, while Foundation uses jQuery. A global replacement is unsafe.
2. Replace ThemeNav BML query/redirect helpers and explicitly propagate redirects
   through widget dispatch. Preserve search/page/show/authas and POST semantics.
3. Migrate customize/index and customize/options into controllers/Foundation
   templates; preserve style initialization, strings, permissions and widgets.
4. Extend tests beyond baseline rendering/title updates to theme application and
   preview, layouts, all option-widget families, reset/save/reload, community
   targeting, old URLs, and responsive rendering. Delete BML pages only when ready.

Independent later work includes settings, remaining FCK poll dialog, entry
picker/parity, inbox parity, translation/request runtime, then engine deletion.
Use the dependency sequence and validation matrix in the removal plan.

## Existing environment and portable setup

Same-machine worktree: `/private/tmp/dreamwidth-bml-20260921`.
Existing container: `4e7a47333842` (verify current availability; IDs are not portable).
Container mount: `/workspaces/dreamwidth`. Its MySQL volume is isolated.
Original checkout `/Users/mark/src/dreamwidth` and the pre-existing
`bml-be-gone` worktree were not modified. Do not repurpose another session's state.

For another machine/window, fetch the branch from zorkian/dreamwidth and create
an isolated worktree from it. Follow AGENTS.md to start its devcontainer:

```bash
npx @devcontainers/cli up --workspace-folder .
docker ps --filter "label=devcontainer.local_folder=$(pwd)" --format '{{.ID}}'
docker port <container-id>
```

Edit/run Git on the host. Run tests/builds/formatting inside the container.
Setup seeds test_user, test_friend, test_paid and test_comm; the browser tests
expect the repository's development seed credentials. See bin/dev/seed-testdata.
Customization integration requires compiled ciel/indil and uses temporary users
in the development database, not the minimal theme-less test database.
The existing test_user title is a test fixture value, not a production title.

## Reproduce validation

Inside the container, with development fixtures:

```bash
prove t/plack-access-filters.t t/widget-request.t t/plack-image-preview.t \
  t/plack-image-dialog.t t/plack-customize.t t/plack-bml.t t/wtf.t \
  t/content-filters.t t/tags-trustmask-count.t t/ml.t
perl extlib/bin/tidyall -a
perl t/02-tidy.t
perl t/00-compile.t
bin/build-static.sh
bin/dev/screenshot /login
node t/browser/access-filters.js
node t/browser/widget-titles.js
node t/browser/image-preview.js /tmp/image-dialog-after
node t/browser/customize-baseline.js /tmp/customize-baseline
```

The screenshot helper installs Chrome/Puppeteer prerequisites. Browser scripts
currently use `/opt/dw-screenshot/node_modules/puppeteer-core`,
`/usr/bin/google-chrome-stable`, and container localhost:8080. Access-filter
browser testing expects test_user initially has no access groups; use a dedicated
seeded container. Baseline capture is not complete customization acceptance.
Restart only your own container's Starman after route/startup changes as AGENTS.md
specifies. Never use desktop browser automation for these checks.

Last recorded combined suite: 261 tests / 10 files passed. Formatting: 1,031
assertions passed. Compilation: 1,597 assertions including existing skips passed.
Full static build passed for access-filter JS. Actual headless flows passed for
access filters, personal/community title RPCs, and image insert/edit/preview.
These results belong to the checkpoint; validate new changes appropriately.

Portable screenshots and customization results are committed under
[bml-evidence/2026-09-21](bml-evidence/2026-09-21/README.md). Raw test logs are only
in the existing container's /tmp; they are not required for a fresh setup and
have not been uploaded. The progress log summarizes their results and limitations.

## Remaining decisions and definition of done

Do not remove beta-gated entry/inbox flows until their parity and cutover gates
are resolved, including sender eligibility and old POST actions. The alternate
ImageButton dialog contains legacy host/upload branches and is not proven
redundant. The root upload-return callback was preserved; no upload service was
certified. Deployed local overlays/BMLInit/AJAX mappings need a deployment
inventory before final engine deletion; production access was not used here.

Done means every inventory item has a tested disposition, compatible routes
remain where needed, and startup/acceptance work with the BML engine physically
absent. Merely eliminating .bml page files, renaming adapters, or retaining a
permanent BML shim does not satisfy that goal.
