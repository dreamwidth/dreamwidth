# BML removal implementation log

## 2026-09-21 overnight pass

- Authorization: implement the removal plan starting with characterization and
  access filters; local reviewable commits, isolated worktree/container, no push,
  deployment, or production changes.
- Baseline: d9ea4bea6. Branch: bml-overnight-20260921.
- Worktree: /private/tmp/dreamwidth-bml-20260921.
- Evidence directory on host: /private/tmp/dreamwidth-bml-evidence-20260921.
- The original checkout and existing bml-be-gone worktree remain untouched.
- Started a dedicated devcontainer with its own MySQL volume.

## Access-filter characterization

Disposition: migrate. Modern navigation still links to this page and there is
no replacement for editing access groups. Reading filters are a different model.
The page does not use LJ::Widget, so its migration does not require the shared
widget refactor first.

Contract to preserve:

- Login and authorized authas selection; communities display an unavailable
  message (they cannot have access filters).
- IDs 1 through 60; names, public flag, order, membership, and existing hidden
  field names. Browser operations: create, rename, delete, reorder, multi-select
  add/remove; changes persist only on Save Changes.
- Validate all comma-containing new/changed names before any mutation.
- Accept both old editfriend_groupmask_USER and split maskhi/masklo fields.
  Preserve bits above 31, including group 60; never restore a trust edge removed
  between page load and submission.
- POST with mode=save requires a valid form token. Save shows a result page with
  links to posting and subscription filters. Other modes render the editor.
- Preserve the script's prohibition on reusing a deleted group ID before saving.

Baseline observations to test:

- Community rejection currently happens after the save branch, so forged saves
  need a regression check and an ownership/type guard before mutation.
- Group methods can return failure; avoid silently claiming a save succeeded.
- Existing JS uses 31-bit halves because JavaScript bit operations are 32-bit.
- Delete clears member bits on the client; verify the server's resulting masks
  and actual entry visibility, including crafted and stale submissions.

## Pending work

1. Finish environment setup; run baseline tests and capture old UI states.
2. Migrate access-filter controller/template/JS/strings with regression coverage.
3. Run behavioral, visual, formatting, compilation and static-build checks.
4. Commit the validated package and continue to independent prerequisites.

Production beta settings/local extensions are outside this isolated pass; do not
remove beta-gated entry/inbox functionality without resolving their cutover gates.

## Access-filter migration completed

- Dedicated container: 4e7a47333842. Old BML page removed; controller, Foundation
  template, extracted JS and relocated translations added. Old .bml URL still
  resolves through modern routing. Updated cross-template translation callers.
- Preserved group IDs, 31-bit mask halves, whole-mask submissions, order/public
  metadata, and save-result links. Community saves are now rejected before any
  mutation; stale submitted masks cannot reintroduce a deleted group bit.
- Added t/plack-access-filters.t: 25 assertions passed against old BML, then 27
  passed against TT with the additional community/stale-save regressions.
  Tests include persistent groups/masks and actual protected-entry visibility.
- Baseline existing content-filter/trustmask/routing tests passed. The fake-cache
  wrapper initially broke the test because the loader shifts cached arrays;
  using the isolated real cache corrected the test fixture.
- t/browser/access-filters.js passed against both implementations: login,
  create/add/save/reload, rename/reorder, remove/delete, community and unauthorized
  authas. Captured empty, populated, mobile, saved, community, unauthorized states.
  Visually inspected the TT desktop and 390px screenshots; no layout overflow.
- Browser testing caught missing JS due to the resource group; fixed by registering
  the extracted script in Foundation. This was not caught by HTTP tests.
- Full tidy apply/check passed (1,025 check assertions), compile passed (1,593
  assertions including existing skips), full static build passed. Targeted suite
  passed: access-filter, wtf, content-filters, tags-trustmask-count, ml (129 tests).
- Evidence: /private/tmp/dreamwidth-bml-evidence-20260921/access-before and
  /private/tmp/dreamwidth-bml-evidence-20260921/access-after/access-after.
- Browser reproduction (inside devcontainer, seeded accounts required):
  `bin/dev/screenshot /login` installs Chrome/Puppeteer if needed; then run
  `node t/browser/access-filters.js`. Script expects test_user to start without
  access groups and cleans up groups it creates on success.

Next: remove shared widget BML input/error dependencies needed by customization;
keep compatibility for surviving BML callers and add request-isolation tests.

## Shared widget request seam completed

- Widget GET/POST inputs, repeated form values, and errors now use the current
  request. Profile and widget RPC callers no longer depend on BML error globals.
  The BML renderer temporarily bridges its error array for surviving pages.
- Invalid CSRF now stops widget dispatch before a handler can mutate data.
  Verified AJAX authorization remains supported and scoped to that request.
- Removed the effective-remote helper's stale BML authas fallback. Tests cover
  current GET/POST identity and isolation from preceding BML requests.
- Real headless testing exposed accumulated customization initialization scripts
  in persistent BML workers: a click could send several RPCs with old tokens.
  Both customization pages now reset headextra before rendering. The browser
  regression asserts one RPC per click, persistent title saves and restoration
  for a personal journal and a maintained community, with no JS errors.
- t/widget-request.t passes 22 assertions. The earlier broader widget/Plack/profile
  run passed 322 tests across 17 files; final affected widget/auth/BML/profile
  run passed 48 tests across four files. Final full tidy check (1,026 assertions)
  and compile check (1,593 assertions including existing skips) passed.
- Reproduction: `node t/browser/widget-titles.js` inside the seeded container.
  Final run passed after restarting Starman. Baseline customization screenshot:
  /private/tmp/dreamwidth-bml-evidence-20260921/customize-before.png.

Next independent package: preserve and migrate the still-used FCK image-preview
iframe. Customization still needs Foundation resource/legacy-JS compatibility
work before its BML pages can be removed.

## Image-preview iframe migration completed

- Moved imgpreview.bml verbatim (including its LGPL notice) into the standalone
  entry/image-preview.tt template. ImagePreview controller preserves /imgpreview
  and /imgpreview.bml, HTML content type, and anonymous iframe access.
- t/plack-image-preview.t passed the same 14 assertions before and after migration.
  BML engine tests now create a temporary executable fixture and verify its output,
  rather than depending on a production page that is being removed. Combined
  HTTP/engine run passed 25 tests.
- t/browser/image-preview.js passed before and after: real modern editor, real FCK
  image dialog, callback element identity, image load, original dimensions, locked
  aspect-ratio resize, alternate text, and insertion into the editor. No entry was
  published. Both final runs had no browser exceptions. An earlier exploratory
  run observed a parent-dialog setupIframeHandlers error; that legacy upload
  helper remains to be assessed with imguploadrte migration.
- Full formatting check passed (1,028 assertions); compilation passed (1,595
  assertions including existing skips). No static asset contents changed.
- Evidence: /private/tmp/dreamwidth-bml-evidence-20260921/image-preview-before and
  image-preview-after. Visually inspected the final dialog screenshot.
- Reproduction: `node t/browser/image-preview.js /tmp/image-preview-after`.

The inventory is now 14 executable/page .bml files plus the original three BML
configuration files; nine .bml.text files and both .look files remain. Engine
removal is still gated on the remaining pages and runtime dependencies.
