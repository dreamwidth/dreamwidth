# BML removal inventory and project plan

Review baseline: `d9ea4bea6`, 2026-09-21. The inventory below records that baseline.
Authorized implementation progress and validation are tracked in
[BML-PROGRESS.md](BML-PROGRESS.md). Access filters and the image-preview iframe
have since migrated; the shared widget request-state prerequisite is complete.

## Findings and scope

The tracked tree contains **16 BML page files (5,034 lines), 3 BML configuration
files, 10 `.bml.text` files, and 2 `.look` files**. There is no page in this
inventory that should be deleted immediately on the strength of its filename
or deprecation comment alone.

“In use” below means a reachable implementation or a caller found in source,
not measured production traffic. Production beta membership, deployed local
overrides, external clients, and access logs were not available to this review.
Existing replacements have not been certified behaviorally equivalent.

The governing documentation is [BML-MIGRATION.md](BML-MIGRATION.md): decide
migrate/deprecate/leave/delete before implementation; preserve behavior, URLs,
form contracts, and strings; restyle normal pages to Foundation; capture old
states before conversion. [PLACK.md](PLACK.md) describes the current runtime;
[SCREENSHOTS.md](SCREENSHOTS.md) documents headless visual capture.

Three findings determine the project structure:

1. The inbox and much of the entry editor already have TT replacements. Finish
   their parity and rollout work instead of porting their legacy copies again.
2. **The modern editor still uses BML dialogs.** `views/entry/form.tt` loads
   FCKeditor and `js/pages/entry/rte.js`; that script activates the `Update`
   toolbar. FCK's image command calls `/imguploadrte.bml`, and its LiveJournal
   plugin calls `/tools/fck_poll.bml`. Removing the old posting form does not
   remove these dependencies.
3. **BML is also shared infrastructure.** Modern translations, widgets, journal
   rendering, request helpers, and some controllers still use its symbols.
   Having zero `.bml` pages is an intermediate milestone, not completion.

## Complete page inventory

All paths in the first column are relative to `htdocs/`. “Migrate” can mean
adapting existing logic to a controller/template, without rewriting its model.

| File | Current use / replacement evidence | Proposed disposition and deletion gate |
|---|---|---|
| `customize/index.bml` | Theme/layout browser; linked from `DW::Logic::MenuNav`. Handles authas, style initialization, search/category/designer/page filters, and widgets. `DW::Controller::Customize` only registers viewuser and preview_redirect; Advanced is separate. | **Migrate.** Retain `/customize/` and its URL variants, widget behavior, and community permissions. No equivalent replacement found. |
| `customize/options.bml` | Current theme options; linked from navigation and theme browser. Handles CustomizeTheme, CustomTextModule, JournalTitles, MoodThemeChooser, NavStripChooser, S2PropGroup, LinksList, and LayoutChooser widgets. | **Migrate**, after removing widget dependence on BML globals. Existing theme widgets/templates are components, not a replacement page. |
| `manage/circle/editfilters.bml` | Access/trust-group editor, linked from modern manage/circle, manage, site index, and subscription-filter templates, plus notification emails. | **Migrate.** `/manage/subscriptions/filters` manages reading filters and `/manage/circle/filter` selects a view; neither replaces access-group editing. |
| `manage/settings/index.bml` | Main settings hub, linked from navigation. Nine categories plus extension hooks, anonymous display settings, authas, and privileged read-only notification inspection. `DW::Controller::Settings` implements accountstatus/password/lostinfo/2FA, not this hub. | **Migrate.** Reuse `LJ::Setting`/`DW::Setting` and tracking components, preserving all category and permission behavior. |
| `editjournal.bml` | Both entry picker and legacy editor. Modern `Entry.pm` still links back to `/editjournal`. Picker supports latest entry, recent N, date selection, and community journals. Per-entry editing redirects to `/entry/<journal>/<id>/edit` for eligible updatepage-beta users. | **Split responsibilities.** Migrate the picker; validate the existing edit/delete implementation and old parameter mapping; then remove the legacy edit form. Do not blanket-deprecate the file. |
| `update.bml` | Legacy posting page. GET redirects beta members to `/entry/new`; POST remains legacy. Already marked deprecated. | **Retire after editor parity/cutover.** Preserve old GET entry points and establish explicit handling of old POST forms. Do not port the form again. |
| `preview/entry.bml` | Called by legacy `js/entry.js`; modern `js/pages/entry/new.js` targets `/entry/preview` in `Entry.pm`. Already deprecated. | **Delete with legacy editor**, after preview parity and caller removal. Preserve any required old endpoint contract in non-BML routing. |
| `tools/endpoints/draft.bml` | Called by legacy `js/entry.js`. Replacement `/__rpc_draft` exists in `Entry.pm`. Already explicitly marked “do NOT migrate.” | **Delete with legacy editor**, after saved-draft compatibility and failure-path tests. Avoid a third draft implementation. |
| `imgupload.bml` | Legacy Insert Image popup, opened through `entry.js`/InOb. Already deprecated; not the FCK image dialog. | **Delete with its last caller.** Account for its shared translation keys before deleting its `.text` file. |
| `imguploadrte.bml` | FCK image dialog called from distributed FCK browser bundles. Its preview iframe points to `/imgpreview`. Modern editor loads this same editor. | **Migrate the standalone dialog**, retaining the FCK callback/DOM contract and legacy URL compatibility. Replacing FCK itself would be a separate product decision, not a prerequisite assumed by this plan. |
| `imgpreview.bml` | HTML image-preview iframe for `imguploadrte.bml`; also the fixture route used by `t/plack-bml.t`. The file contains HTML/JS, not server-side BML blocks. | **Move to an appropriate static asset or standalone TT route**, update its caller, and preserve compatibility if needed. Keep preview behavior; remove dependence on BML dispatch. |
| `tools/fck_poll.bml` | FCK LiveJournal plugin's poll wizard. Modern editor still loads that plugin. `/poll/create` exists but is not a drop-in replacement for this dialog's callbacks. | **Migrate the standalone dialog**, reusing poll logic where appropriate and preserving insert/edit/round-trip behavior. |
| `stc/fck/editor/dialog/imguploadrte.bml` | Alternate FCK image dialog. A relative `ImageButton` reference remains in `fckeditorcode_gecko_2.js`; other bundles use the root dialog. The configured Update toolbar does not expose ImageButton. | **Conditional delete/consolidate**, not proven dead. Establish which bundles/configurations can reach it, test static-vs-dynamic dispatch, then remove the duplicate and obsolete reference or point a supported caller at the migrated dialog. |
| `inbox/index.bml` | Legacy inbox. GET redirects inbox-beta members to `/inbox/new`; legacy POST still processes old action names. Replacement is `DW::Controller::Inbox` and `views/inbox/index.tt`. | **Retire after inbox parity/cutover.** Keep old URLs and query semantics, with deliberate old-POST handling. |
| `inbox/compose.bml` | Legacy PM composition/reply page. Replacement `/inbox/new/compose` exists. The legacy page remains independently reachable; its deprecation note is not a redirect. | **Retire after compose parity**, including recipients, reply authorization, validation, and old links/forms. |
| `inbox/markspam.bml` | Legacy PM spam/ban flow. Replacement `/inbox/new/markspam` exists. Both implementations remain reachable. | **Retire after action/error parity** and caller migration, including links generated by notification objects. |

### Companion files

The ten translation files are the `.bml.text` companions of:

- `customize/index`, `customize/options`;
- `editjournal`, `update`, `preview/entry`, `imgupload`;
- `inbox/index`, `inbox/compose`;
- `manage/circle/editfilters`, `manage/settings/index`.

For migrations, move strings to the appropriate TT scope and update every
cross-page caller. For replacements, compare the existing TT strings before
retiring the old keys; do not overwrite the replacement's translations wholesale.
In particular, the FCK image dialogs use `/imgupload.bml.*`, and modern manage
templates use `/manage/circle/editfilters.bml.title2`. The old preview also
references `/poll/create.bml.error.accttype2` even though that page is migrated.

Update `bin/upgrading/deadphrases.dat` and validate the translation loader's
file/DB/cache paths. `texttool.pl` deliberately supports moved keys surviving a
mixed-version deployment: do not prune translations while old workers need them.

The three configuration files are `htdocs/_config.bml`,
`ext/dw-nonfree/htdocs/_config.bml`, and
`ext/dw-nonfree/htdocs/_config-local.bml`. They establish look roots, language,
scheme, code permissions, and initialization. Remove them only with engine
retirement, after retaining applicable language/scheme behavior in modern config.

## Runtime inventory beyond pages

| Area | Files / dependencies | Required work |
|---|---|---|
| Dispatch and engine | `app.psgi`, `cgi-bin/DW/BML.pm`, `cgi-bin/Apache/BML.pm` | Remove fallback resolution/rendering and the legacy AJAX map path only after routes are covered. Default AJAX mappings are currently empty, but deployed overrides need checking. Remove Apache/APR loading stubs with their last consumer. |
| Blocks and initialization | `cgi-bin/lj-bml-blocks.pl`, `cgi-bin/LJ/Global/BMLInit.pm`, `cgi-bin/bml/scheme/{global,tt_runner}.look` | Remove parser/block/config hooks and look files after page and helper consumers disappear; audit `LJ::Local::BMLInit` extension loading. |
| Translations | `LJ::Lang`, `Plack::Middleware::DW::RequestWrapper`, `LJ::S2`, `LJ::Protocol`, `LJ::Web`, controllers and event classes | `LJ::Lang::ml` still delegates to `BML::ml` in web context. Establish native request-scoped language and scope resolution before replacing direct calls. Preserve debug language, fallback, substitution, and background-job behavior. |
| Request compatibility | `DW::Controller::Journal`, `LJ::S2`, `LJ::Protocol`, `LJ::UniqCookie`, `LJ::User::Login`, `LJ::Comment`, `LJ::Talk`, `LJ::Sysban`, `LJ::PageStats`, `LJ::Config` | Journal pages and feed hooks use `DW::BML::RequestAdapter`. Move supported behavior to `DW::Request` or a narrowly scoped non-BML adapter; cover cookies, headers, notes, statuses, IPs, redirects, and conditional responses. |
| Widget/form globals | `LJ::Widget`, `LJ::Web`, `LJ::User::Login`, `DW::Controller::Manage::Profile`, `DW::Controller::RPC::MiscLegacy` | Replace `%BMLCodeBlock::GET/POST`, global error arrays, parameter declarations, and authas fallbacks with explicit request/input/error state. Modern profile and widget RPC already depend on the global error array. |
| HTML helpers | `LJ::Web`, `LJ::Widget::InboxFolder`, theme widgets, setting classes | Remove legacy `entry_form`/`entry_form_decode` with their callers; retain shared helpers after making them independent of BML. Audit generated `<?...?>` blocks as well as named BML calls. |
| Siteschemes/template bridge | `DW::SiteScheme`, `DW::Template`, `LJ::Setting::SiteScheme`, login/logout | Remove `tt_runner`, BML scope handling and scheme APIs without removing TT journal/site rendering. The `BMLschemepref` cookie name is a compatibility contract; retaining its name does not require retaining the engine. |
| Modern controller stragglers | Customize::Advanced, MassPrivacy, RPC::CutExpander, Tools, Support::Faq, Support::Request, Admin::FAQ | Replace BML translation/redirect/default-language/modification-time calls with modern equivalents and test their behavior. |
| Other live consumers | Events/notifications, Message, Poll, S2 page classes, DW::User::Rename, DW::Hooks::Changelog, account display widgets/settings | Convert translation and request-helper calls even though their source files are not pages. Include CLI/worker execution in validation. |
| Tooling and docs | `t/plack-bml.t`, `t/00-compile.t`, `LJ::Lang` legacy key handling, `texttool.pl`, `doc/template.bml.txt`, migration/Plack docs | Replace useful route/security assertions rather than just deleting tests; remove compile exclusions and obsolete authoring instructions. Keep historical strings/documentation only where intentional. |

Do not mass-delete everything containing “bml”: old URL aliases, translation
history, and compatible cookie names can survive without a parser. Conversely,
renaming an adapter or keeping a permanent `BML::*` shim is not completion.

## Replacement gaps to characterize first

These are source-review findings, not failures reproduced in a running site:

- Inbox compose's rejected-recipient branch calls `errors->add` instead of
  `$errors->add` (`Inbox.pm`, around line 551). Exercise the branch explicitly.
- Legacy compose checks the sender's `is_validated`; the modern handler's
  corresponding early check is `user_messaging`, with a validation-related
  message. Establish intended sender eligibility and test both flows.
- Modern markspam records a “No action selected” error but then redirects from
  the POST branch without rendering that error. Compare the legacy response.
- Legacy inbox button names (`markRead_*`, etc.) and modern action names differ.
  Redirecting an old POST cannot be assumed to preserve the action.
- Both inbox implementations have bookmark actions reachable through GET.
  Record this contract and explicitly decide/test the intended safe mutation
  behavior at cutover rather than accidentally changing it through routing.
- The BML migration guide still mentions `Apache/LiveJournal.pm` as a routing
  edit location; the current Plack dispatch lives in `app.psgi`. Follow the
  checked-out implementation, not that historical filename.

## Proposed work sequence

Each numbered package should be independently reviewable; split large packages
into successive PRs by behavior. No calendar estimate is implied.

1. **Characterization and acceptance ledger.** Enumerate GET/POST actions and
   parameters for every row above, attach expected effects and test cases, and
   capture baseline page states in an isolated devcontainer. Record old/new
   behavior separately. Inspect deployment beta settings and local overlays;
   use available route traffic to identify external/old clients. Treat absent
   traffic as supporting evidence, not proof of dead functionality.
2. **Shared form/widget seam.** Remove global BML input/error dependencies needed
   by customization, settings, profile, and widget RPC. Add explicit error-path,
   CSRF, repeated-field, authas, and sequential-request tests. Preserve working
   BML callers until their pages migrate.
3. **Migrate access filters.** This is a bounded first end-to-end page migration.
   Preserve IDs, names, memberships, ordering, default/reserved groups, and
   authorization. Verify entry visibility, not just the editor's success page.
4. **Migrate customization, then settings.** Customize browser/options can be
   separate PRs over the shared widgets. Move the settings shell and then verify
   each category/setting family, notification actions, hooks, anonymous settings,
   community authas, and privileged read-only views. Preserve existing components.
5. **Complete inbox replacement.** Characterize/fix the gaps above, cover all
   inbox/compose/spam flows, settle the public route mapping, and update all
   callers (including notification-generated links). Remove the inbox beta gate
   and all three legacy pages only after the acceptance matrix passes.
6. **Remove modern editor's BML dependencies.** Migrate image and poll dialogs;
   move the preview HTML; resolve the duplicate static-tree dialog. Exercise the
   actual modern RTE toolbar and callbacks. Do not expand this package into an
   unsolicited rich-text-editor replacement.
7. **Finish entry migration and cutover.** Add the missing entry picker, verify
   new/edit/delete/preview/draft parity, map legacy query and form contracts, and
   promote the replacement. Remove update, legacy edit form, old preview/draft/
   image popup, plus only assets and helpers proven exclusive to them. FCK assets
   remain if the modern editor still needs them.
8. **Replace the remaining shared BML services.** Separate PRs for language,
   request/journal/feed adapters, shared helpers, sitescheme bridge, and remaining
   callers. Language/request work can begin earlier, but must remain compatible
   with any pages still awaiting migration.
9. **Remove the engine and prove independence.** Delete the dispatcher fallback,
   engine modules, blocks, looks, initialization, configs, obsolete tests and
   compile exclusions. Update docs/tooling and add a regression guard against
   reintroducing executable BML or runtime BML dependencies.

Dependency gates: (2) precedes widget-based migrations; (6) and picker/parity
work precede editor deletion; all page removals and (8) precede (9). Inbox work
does not depend on finishing the editor. The final architecture uses controllers,
TT, modern request/language helpers, and compatibility routes where required.

## Validation matrix

| Workstream | Unit / HTTP integration coverage | Headless browser coverage |
|---|---|---|
| Access filters | Create/rename/delete/reorder/membership; repeated values; Unicode/limits; invalid CSRF; unauthorized authas; persistence and actual access masks | Add/remove multiple members, save/reload, reorder, validation state, personal/community variants |
| Customization | Search/filter/pagination; style/layer ownership; widget submissions; invalid authas/CSRF; settings survive reload | Select and preview theme, customize each widget family, reset/save options, navigate groups, community theme, responsive layout |
| Settings | All nine categories and hook-added settings; allowed/denied actors; anonymous cookie settings; read-only inspection; notification add/delete/inactive cleanup; validation and ret_url handling | Tabs, JS controls, unsaved changes, validation with preserved inputs, notifications, account/community variants |
| Inbox | View/folder filters, pagination boundaries, mark read/unread/all, delete/all, bookmarks/limits, archive flag; message ownership; CSRF; recipient eligibility/limits/rate limits; reply; spam-only/ban-only/both/neither | Expand/collapse, multi-select actions, last-item deletion, unread counts, compose/reply/CC, errors, no-JS form paths, spam confirmation |
| Entry picker/editor | Latest/recent/date/community selection; entry IDs and visibility; own/maintainer permissions; draft save/restore/clear across old/new formats; post/edit/delete; security and metadata; moderation/crosspost boundaries | HTML/RTE switching, image insert/edit/preview, poll insert/edit, draft restoration, preview popup, validation, published-entry round trip |
| Translation/widget runtime | Scoped and full keys, substitutions, fallback/debug languages, missing keys, cold/warm DB/file caches; widget errors/inputs; independent sequential requests | No raw ML keys/BML blocks; representative translated modern, journal, error, and settings pages |
| Request/journal runtime | Cookies/login/logout, IP/header/status handling, request teardown, journals/entry/day/month/read/tag, feed hooks, conditional GET, errors/captcha/adult interstitials | Login/session continuity, journal/site scheme selection, protected content, interstitial return flow |
| Dispatch removal | Old `.bml`, extensionless, slash and index aliases; query preservation; POST bodies/actions; unknown paths; `_config` and traversal rejection; RPCs | Existing bookmarks/navigation/email links reach the intended modern flow; no failed dialog/RPC requests |

For each mutation assert the persisted result and reload it through the user
flow; a 200 response, flash message, or screenshot alone does not prove success.
For denied actions assert no mutation occurred. Test relevant logged-out,
unvalidated, normal, paid, suspended, community-manager and privileged actors.

Use isolated seeded data, including empty and populated states, multi-page
inboxes, multiple access groups, community entries, existing polls, saved drafts,
and invalid inputs. Stub external mail/crosspost effects in automated tests.
Do not make validation depend on messaging real users or publishing real posts.

Run browser tests headlessly inside the devcontainer. `bin/dev/screenshot`
provides full-page visual evidence but is not a behavioral test suite: use
headless scripted interactions with assertions, browser console/network error
collection, and durable test fixtures for JS workflows. Capture old states
before deletion and corresponding new states with the same data. Standalone FCK
dialogs must preserve their embedding/callback contracts rather than acquire a
normal site wrapper. Include narrow and desktop viewports and keyboard use.

## Existing tests and release checks

Reuse and extend `t/settings.t`, `t/content-filters.t`, `t/notificationinbox.t`,
`t/notificationmethod-inbox.t`, `t/poll.t`, `t/post.t`,
`t/proto-post-edit-roundtrip.t`, `t/entry-lookup.t`, `t/draftset.t`, `t/ml.t`,
the routing/request/Plack suites, and relevant authentication/access tests.
These are starting points, not evidence that page behavior is already covered.
`t/plack-bml.t` currently exercises basic resolution/rendering and security using
`/imgpreview`; preserve useful HTTP/security assertions in successor tests.

Before each implementation PR, run repository-required formatting and compilation
checks and the workstream's behavior tests inside its devcontainer. Build static
assets for relevant JS/CSS changes and restart Starman for new routes/startup
changes. Before final removal, run the full applicable suite including language,
notifications, polls, settings and content filters, plus headless acceptance.

The inspected `.github/workflows/ci.yml` checks changed-file formatting, all-module
compilation, request/Plack/cleaner/routing/auth/post/comment/access groups. It does
not list browser acceptance, `t/ml.t`, `t/poll.t`, `t/notificationinbox.t`, or
`t/content-filters.t`; a green fast CI job is insufficient for this project.

Keep rollout reversible through small commits and deployment rollback. Preserve
translation data through mixed-version deployment. For old GET URLs prefer
aliases/redirects with query preservation; for POST use deliberate compatible
dispatch or a tested adapter rather than a blanket 301/302 that loses the body.
Routing already treats the `bml` format as an ancient-link compatibility case;
test and retain that behavior where useful without retaining the engine.

## Definition of done

- Every inventory row has a completed disposition and passing acceptance evidence;
  no functionality silently disappears because its container was a BML file.
- No executable `.bml`, BML configuration/look file, parser, code-block machinery,
  runtime `BML::*`/`BMLCodeBlock::*` call, or BML dispatcher remains.
- The app starts and the acceptance suite runs with `DW/BML.pm` and
  `Apache/BML.pm` physically absent; no `%INC` stubs or hidden requires mask a
  dependency. Modern pages, journal pages, feeds, APIs and background paths work.
- Request language/input/error state does not leak across successive requests in
  a persistent worker. Production-like cached/multi-worker behavior is covered.
- All public URLs, old links/forms, permissions, translations, assets, and feature
  gates have an explicit compatibility or retirement decision. Deployed local
  extensions have been audited before final engine deletion.
- Runtime/static scans and browser network traces reveal no unexplained legacy
  dependency. Any remaining “BML” text is documented history or an intentional
  compatibility identifier, not executable infrastructure.

Continue with remaining independently testable packages after their listed
prerequisites pass. The progress log records completed packages and known gates.
