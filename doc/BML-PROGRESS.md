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
