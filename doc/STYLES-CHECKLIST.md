<!--
STYLES-CHECKLIST.md: A contributor's checklist for Dreamwidth style changes.

Authors:
    SAPHID

Copyright (c) 2026 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.  For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.
-->

# Before you commit a Dreamwidth style change

Use this with your diff open. It's for anyone touching journal styles or the appearance and
controls of a site page, even if the change is only one line. Pick the checks your change can
break; this is not a new style policy.

## Quick pass

1. **Name the user-facing result.** What's broken or missing today, and what will be different?
   Separate unrelated changes before reviewing the diff.
2. **Put the fix where it belongs.** A new palette for Lefty belongs in its *theme*; a new
   arrangement of its entries belongs in its *layout*. For shared behavior, use the narrowest
   layer that owns it. The inbox, login form, and Customize wizard are *site pages*: their own
   appearance follows the site skin, not the selected journal theme.
3. **Verify the code you changed.** For a fix, reproduce the bug before applying the patch.
   [Load the changed code](#test-what-you-changed), then repeat the steps and try one nearby case
   that should stay the same. For new behavior, exercise it alongside an existing case.
4. **Make the commit match what you tested.** Read `git status --short` and `git diff --cached`.
   Check that the commit includes the files it needs (such as a theme preview or updated test)
   and leaves out debug output, build output, and unrelated edits. `git diff` shows tracked edits
   you haven't staged: if the tested files differ from the staged version, stage the tested
   version or recheck the version you intend to commit.

The examples explain why these checks matter. **Decision** means someone gave a reason in the
linked PR; **pattern** means merged patches demonstrate the advice. The test table also draws on
the project's existing wiki.

## Changing a theme or shipping a layout

- **Package a theme so a user can select it.** In the layout's `themes.s2`, follow a neighboring
  `#NEWLAYER` block. Give it a unique `layout/theme` key, display name, and the designer's credit.
  Match the preview filename to the key in `htdocs/img/customize/previews/<layout>/`. Include any
  header or background art the theme actually loads: the chooser thumbnail isn't the artwork.
  Adding a palette to an existing layout normally needs no new Perl module. **Pattern:**
  [five Lefty palettes, two designers](https://github.com/dreamwidth/dreamwidth/pull/1437);
  [Heads Up previews and header art](https://github.com/dreamwidth/dreamwidth/pull/1814).
- **A new layout has more moving parts.** Choose its parent first: [the layer registry](../styles/s2layers.dat)
  includes a separate list for Tabula Rasa children. Register the layout and its themes under
  the right parent. Set the default theme in [the theme chooser](../cgi-bin/LJ/S2Theme.pm)
  and declare the supported column arrangements in the layout's subclass, as in
  [Venture's `layouts` method](../cgi-bin/LJ/S2Theme/venture.pm). Check that the layout appears, its default
  preview matches what opens, and the wizard offers only arrangements it can render.
  **Pattern:** [Venture](https://github.com/dreamwidth/dreamwidth/pull/1876) and
  [Gold Leaf](https://github.com/dreamwidth/dreamwidth/pull/1877).
- **Trace a setting from the wizard to the result.** Reuse an existing core property if it means
  the same thing. If you add one, put it in the relevant wizard group, consume it in the layout,
  and try both its default and a visibly different value. Planet Caravan needed a footer text
  setting because users had no way to correct black labels on black footers; the fix also set
  legible values in the affected themes. **Decision:** [footer contrast](https://github.com/dreamwidth/dreamwidth/pull/1442).
  If an existing property starts styling another part of the page, update its description and
  check other layouts that use it: [interaction and management links](https://github.com/dreamwidth/dreamwidth/pull/493).
  **Pattern:** [wizard ordering](https://github.com/dreamwidth/dreamwidth/pull/1912),
  [applying header image settings](https://github.com/dreamwidth/dreamwidth/pull/2405).
- **Check color pairs where they actually appear.** Header links can sit on a different
  background from entry links. Look at ordinary, visited, hover, and active links against that
  region's background; hover a *visited* link too. For equal-specificity CSS rules, put the
  ordinary link first, then `:visited`, `:hover`, `:active`, so the hover still shows.
  **Decision:** [ninetyd's review and Momiji's reply](https://github.com/dreamwidth/dreamwidth/pull/487).
  Don't fix one preset by hard-coding its color
  in the layout. Generate font CSS from the selected family, fallback, size, and unit rather
  than rebuilding the declaration by hand. **Pattern:** [header links](https://github.com/dreamwidth/dreamwidth/pull/82),
  [link state conflicts](https://github.com/dreamwidth/dreamwidth/pull/485),
  [font generation](https://github.com/dreamwidth/dreamwidth/pull/1882).
- **Check what the parent layout already styles before adding an override.** If a rule loses,
  identify the competing selector first. In Tectonic, targeting the navigation module rather
  than every module let the layout override the parent without a string of `!important`
  declarations. That's a preference for a narrower selector, not a ban on `!important`.
  **Decision:** [Tectonic CSS review](https://github.com/dreamwidth/dreamwidth/pull/317).

## Changing shared journal behavior

- **Put a shared fix in the smallest layer that owns it.** Several styles needing a change
  doesn't make it a core2 change. **Pattern:** [the interaction link change](https://github.com/dreamwidth/dreamwidth/pull/493)
  updated property descriptions in core2 but styled the links in Tabula Rasa.
- **Treat shipped property names as an interface.** Updating every bundled theme is not enough:
  users have layers you can't edit. Momijizukamori closed a naming cleanup after feedback:
  “90d pointed out that this breaks user customizations”. **Decision:**
  [unmerged Planet Caravan rename](https://github.com/dreamwidth/dreamwidth/pull/484).
  For a migration, distinguish an old default from text a user deliberately set; see the
  [custom text fix](https://github.com/dreamwidth/dreamwidth/pull/614).
- **Call the shared print function, then override the smallest piece that differs.** In
  Drifting, the recent-entries page needs a reply container for a particular entry; the
  individual entry page needs the top-level reply target. Routing both through
  `print_entry_footer` lets each page supply the right target. When changing this shared path,
  open QuickReply on the second of two Recent entries and on a single Entry. Check that it
  attaches to the right post in a layout that inherits the helper and one that overrides it,
  such as Drifting. **Pattern:** [Drifting QuickReply](https://github.com/dreamwidth/dreamwidth/pull/1914);
  see the `Page::print()` guidance in [core2](../styles/core2.s2).
- **Give custom CSS a hook that describes the content.** A frozen-comment label isn't a link;
  a navigation item shouldn't need to be selected by its position. When shared markup changes,
  search sibling layouts for overrides and selectors that still expect the old markup. Keep
  user-authored content distinguishable from site controls (`usercontent`). **Pattern:**
  [frozen label](https://github.com/dreamwidth/dreamwidth/pull/52),
  [navigation classes](https://github.com/dreamwidth/dreamwidth/pull/2406),
  [comment content](https://github.com/dreamwidth/dreamwidth/pull/327),
  [credit module CSS cleanup](https://github.com/dreamwidth/dreamwidth/pull/389).
- **Put the space between a label and its value in the markup.** Don't ask a user editing a
  text property in Customize to preserve an invisible trailing space. Put the separator *after*
  the label's closing `</span>` so styling the label doesn't style the gap as well.
  **Decision:** [review of the layout credit module](https://github.com/dreamwidth/dreamwidth/pull/369).
- **Design for missing pieces, not just the preview journal.** A post may have no userpic,
  a sidebar may be narrow, and the journal owner may turn off the layout's stylesheet. Check
  that images shrink rather than overflow. Disabling the layout stylesheet alone must not
  suppress the mobile viewport; the separate mobile opt-out still applies.
  **Pattern:** [no userpic](https://github.com/dreamwidth/dreamwidth/pull/97),
  [proportional icon sizing](https://github.com/dreamwidth/dreamwidth/pull/394),
  [viewport with custom CSS](https://github.com/dreamwidth/dreamwidth/pull/2393).

## Changing site pages and skins

- **Start with the shared component; put the exception where it belongs.** Use the
  [site component guide](../views/dev/style-guide.tt) for Foundation forms, tables, and grids.
  Put shared skin color defaults in [the skin variables](../htdocs/scss/skins/_skin-colors.scss)
  and override them per skin where needed. Scope a page-specific selector narrowly enough that
  it doesn't restyle a widget embedded on that page. **Pattern:**
  [highlight-box defaults](https://github.com/dreamwidth/dreamwidth/pull/2590),
  [table styling](https://github.com/dreamwidth/dreamwidth/pull/3241),
  [a date picker caught by a table rule](https://github.com/dreamwidth/dreamwidth/pull/3306).
- **Preserve meaning when changing appearance.** Choose a heading by its place in the page,
  not its font size. Use a real button for an action. Give an icon-only control a text name;
  check focus with the keyboard, not just whether a mouse click works. Within a form, make a
  button that only opens a picker `type="button"` so it doesn't submit the form. **Decision:**
  [keyboard navigation in the login modal](https://github.com/dreamwidth/dreamwidth/pull/3269).
  **Pattern:** [heading size](https://github.com/dreamwidth/dreamwidth/pull/3237),
  [tag picker button](https://github.com/dreamwidth/dreamwidth/pull/3306).
- **Keep the ordinary form useful without JavaScript.** For an enhanced workflow, try the
  underlying submit path with scripting off, then turn it on and check the first paint as well
  as the interaction. An inbox fix kept buttons available without JS while preventing a flash
  of the wrong controls with JS. **Pattern:** [inbox controls](https://github.com/dreamwidth/dreamwidth/pull/3087).
  For a major redesign, consider an opt-in beta: after an accidental rollout and user feedback,
  the team restored the old inbox alongside the new one. **Decision:** [inbox beta after rollout](https://github.com/dreamwidth/dreamwidth/pull/2970).
- **On a BML conversion, test the submitted form, not just the new view.** Keep field names,
  URLs, selected values, and error behavior. Use the form helpers and escape dynamic values for
  their output context. The [migration guide](BML-MIGRATION.md) separates a Foundation restyle
  from a redesign and explains how to move translation files and retire old phrase keys.
  If a manager can select a community, save a change there and verify that **the community
  changed and the manager's personal journal did not**. Check each form that passes `authas`;
  [the first fix](https://github.com/dreamwidth/dreamwidth/pull/3364) missed
  [a second Customize page](https://github.com/dreamwidth/dreamwidth/pull/3431). **Pattern:**
  [retaining input after an error](https://github.com/dreamwidth/dreamwidth/pull/3528).

## Test what you changed

**Load the changes before opening the page.** Run these in the devcontainer, not against a
live site:

- **SCSS, previews, or theme art:** Run `bin/build-static.sh` after changing the source, even
  for an image-only change. Reload and check the edited rule in the browser inspector or
  confirm the new image appears in the chooser or on the journal, as appropriate. Stage the
  source SCSS and image files you changed, not the built copies.
- **Bundled S2 layers:** Run `bin/upgrading/update-db.pl -r -p` against your development database
  to load and compile changed system layers. Look for the `Populating public system styles (S2)`
  section and check that the changed layers and affected themes compile without errors before
  comparing browser output.
  [Patsy's layout once compiled while its theme did not](https://github.com/dreamwidth/dreamwidth/pull/105).

**Pick cases the diff can break, not every row.** For a one-color fix, try the affected state and
a nearby state that should be unchanged. Add cases when the diff crosses a shared layer,
changes a saved setting, or affects an interaction.

| If you changed… | Try this |
| --- | --- |
| A palette, font, or preview | Look at the changed text on its actual background. If the preview changed, compare the chooser image with a journal using the theme. |
| A shipped S2 property or its rendering | Save a non-default value before applying the patch. After reloading the layers, verify that the saved value still applies **without resaving**. Check the default on an untouched journal. |
| Shared entry or comment output | Try the affected view and a sibling view. For shared code, cover a layout that inherits it and any affected override. Pick a state the bug depends on, such as comments disabled, a collapsed thread, or a missing userpic. |
| Layout geometry | Try the affected column arrangement and viewport, plus an adjacent arrangement or breakpoint. Add long titles or larger text if affected. If the change affects the space beside a sidebar, [stress-test journal content](#wide-content-beside-sidebars). |
| A site style or template | Check the local page first. If a shared rule changed, try another consumer and the affected skins. For changed controls or forms, try the action with the keyboard and check fallback submission with JS off where supported. |
| A form's submission or error handling | Check a successful submit and [retry after a failed submit](#retry-after-a-failed-submit). |

For a full submission, the [theme checklist](https://github.com/dreamwidth/dreamwidth/wiki/Theme-checklist) and
[layout submission tests](https://github.com/dreamwidth/dreamwidth/wiki/Testing-layout-submissions)
give more cases. If you can't run a relevant check, say what you couldn't verify rather than
reporting it as passed.

### Retry after a failed submit

Change a prefilled value, if the form has one, and deliberately leave another field invalid.
Submit, then check that all relevant errors appear and that no changes were saved if the form
rejected the submission. On the error page, verify that the edited value and any hidden field
that tracks a choice still match what you submitted. Correct only the invalid field and retry
without re-entering the other values. Verify that the retry saves what you intended. If JavaScript
tracks a choice, also check fields that are already populated when it starts, before any typing or
clicking (for example, restored values or browser autofill).

### Wide content beside sidebars

On a journal using the affected layout, narrow the viewport until the sidebars are just about to
stack. Put an oversized image or a long preformatted line in an entry or comment, and open a
deeply indented comment thread. Check that nothing paints over the sidebar and that you can reach
the wide content and the last reply. Narrow the viewport a little more and check the stacked
layout too. If the layout doesn't stack, use a narrow width where its columns are still visible.

## Give the reviewer a check they can repeat

Keep the `CODE TOUR:` about the user-visible result. In the technical part of the PR, record
the state, steps, expected result, and any relevant checks you did not run. For example:

> CODE TOUR: The inbox paging controls no longer clip on narrow screens.
>
> Signed in to `/inbox/new` with enough messages for two pages, in Chromium at 390 px using
> Celerity. On page 1, both pagers were clipped before the change and fit after it. From each
> pager, page 2 opened and page 1 opened again. The 1024 px layout looked unchanged.
> Other skins not checked.

For a visual change, compare the same page state and viewport before and after. Use the
[screenshot guide](SCREENSHOTS.md) when showing the difference, and follow the
[migration guide](BML-MIGRATION.md#13-screenshots-before-and-after) for BML conversion evidence.

## Where the advice comes from

The research set is 322 distinct public PRs in `dreamwidth/dreamwidth` (August 2012 through
October 2026): 242 authored by `momijizukamori`, 53 by `rshatch`, and 27 by other authors
with comments or reviews from those accounts. The scope follows public project work: for example,
[the FAQ conversion](https://github.com/dreamwidth/dreamwidth/pull/2661) was opened by one
account from the other's branch. These are counts of PRs examined, **not** 322 style changes
or a claim that every line of every diff was read. Backend-only PRs supply no style rule.
A merged designer submission shows how
Dreamwidth packaged the work, not that the submitter personally designed it. A rejected change
is cited as a decision, not as code that shipped. For older wiki advice, check the current
layout or component before copying an implementation detail.
