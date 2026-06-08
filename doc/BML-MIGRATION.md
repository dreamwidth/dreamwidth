# Migrating BML pages to Template Toolkit

BML ("Block Markup Language") is the 20+-year-old LiveJournal page format that
mixes Perl, HTML, and translation calls in a single `.bml` file under `htdocs/`.
It is deprecated. We are steadily converting BML pages to the modern Dreamwidth
architecture, which separates the three concerns:

| Concern | BML (old) | Modern (new) |
|---------|-----------|--------------|
| Logic   | `<?_code … _code?>` blocks in `htdocs/<path>.bml` | a controller in `cgi-bin/DW/Controller/…pm` |
| Markup  | HTML in the same `.bml` file | a Template Toolkit template in `views/<path>.tt` |
| Strings | `htdocs/<path>.bml.text` | `views/<path>.tt.text` |

This document is the how-to. The worked example throughout is the conversion of
`/mobile/login` (see the commit that introduced this file).

> **Run everything in the devcontainer.** All commands below assume you are
> inside the devcontainer (`$LJHOME` = `/workspaces/dreamwidth`). See
> `CLAUDE.md` for container setup, and always work in a git worktree.

---

## 1. Anatomy of a migration

A single `.bml` page becomes (typically) three new files, plus small edits to a
couple of shared files:

```
htdocs/manage/invites.bml         ─┐
                                   ├─►  cgi-bin/DW/Controller/Manage/Invites.pm   (logic)
                                   └─►  views/manage/invites.tt                   (markup)
htdocs/manage/invites.bml.text     ──►  views/manage/invites.tt.text             (strings; git mv)
htdocs/stc/invites.css             ──►  inlined into the .tt, or kept as a file   (styles)

bin/upgrading/deadphrases.dat      ◄──  retire the old `/…bml.*` translation keys
cgi-bin/Apache/LiveJournal.pm      ◄──  remove any hard-coded `.bml` route/redirect (some pages)
any caller of the old ML keys      ◄──  repoint `dw.ml('/old.bml.key')` → new `.tt` key
```

The URL stays the same: `htdocs/manage/invites.bml` was served at `/manage/invites`,
and the controller registers exactly that path.

---

## 2. The controller

Create `cgi-bin/DW/Controller/<Name>.pm`. Controllers are auto-loaded — there is
no registry to update; the `register_string` call at load time wires up the route.

Minimal skeleton:

```perl
package DW::Controller::Manage::Invites;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( "/manage/invites", \&invites_handler, app => 1 );

sub invites_handler {
    my ( $ok, $rv ) = controller( anonymous => 0, form_auth => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $u = $rv->{u};

    # ... build display-ready data, stuff it into $rv ...
    $rv->{invites} = \@invites;

    return DW::Template->render_template( 'manage/invites.tt', $rv );
}

1;
```

### The `controller()` helper

`controller()` (from `DW::Controller`) replaces the BML login/captcha/`$remote`
boilerplate. It returns `( $ok, $rv )`; on failure `$rv` is a ready-to-return
error/redirect response, so the idiom is always:

```perl
my ( $ok, $rv ) = controller( … );
return $rv unless $ok;
```

On success `$rv` is a hashref pre-seeded with:

- `$rv->{r}` — the `DW::Request` object
- `$rv->{remote}` — the logged-in viewer (or `undef`)
- `$rv->{u}` — the *target* user (same as `remote` unless `authas`/`specify_user`)
- `$rv->{authas_html}` / `$rv->{authas_form}` — when `authas` is requested

Pass `$rv` straight to `render_template` as the variable hash; add your own keys
to it as you go.

Common options (full list in `cgi-bin/DW/Controller.pm`):

| Option | Effect |
|--------|--------|
| `anonymous => 1` | allow logged-out visitors (default `0` = require login) |
| `form_auth => 1` | auto-check the CSRF token on POST (pair with `[% dw.form_auth %]`) |
| `authas => 1` or `authas => { … }` | allow `?authas=`, build the switch-user form |
| `specify_user => 1` | allow `?user=` to load `$rv->{u}` |
| `privcheck => [ … ]` | require one of the listed privs |
| `skip_captcha => 1` | never captcha (use sparingly) |

### Routing

```perl
DW::Routing->register_string( "/manage/invites", \&handler, app => 1 );  # exact path
DW::Routing->register_regex( '^/confirm/(\w+\.\w+)', \&handler, app => 1 ); # captures → @_
```

`app => 1` means the site-app context (the normal case). One controller may
register several routes (e.g. `/register` plus `/confirm/…`).

### Reading input

Use the `DW::Request` accessors — they replace BML's `%GET` / `%POST` /
`LJ::did_post()`:

```perl
$r->did_post          # was: LJ::did_post()
$r->post_args->{user} # was: $POST{user}
$r->get_args->{foo}   # was: $GET{foo}
$r->query_string
```

### Rendering

```perl
return DW::Template->render_template( 'manage/invites.tt', $rv );
```

The template name is the path under `views/`. The third argument is an `$extra`
hashref of options; the important one is **`no_sitescheme`**:

```perl
# render the template ALONE — it must emit its own full <html> document
return DW::Template->render_template( 'mobile/login.tt', $rv, { no_sitescheme => 1 } );
```

Most pages render *inside* the Foundation site scheme (omit `no_sitescheme`); the
template then supplies only the page body plus `sections.*`. Standalone pages
(the mobile interface, popups, some tools) emit their own `<html>`…`</html>` and
pass `no_sitescheme => 1`.

### Redirects

```perl
return $r->redirect( "$LJ::SITEROOT/mobile/?t=" . time() );  # was: BML::redirect(...)
```

---

## 3. The template

Create `views/<path>.tt`. The DW plugins (`dw`, `form`) and the `site` namespace
are loaded automatically (via `_init.tt`), so you can use them without `USE`.

### Sitescheme pages: sections

A sitescheme page provides the body plus named sections rather than a whole
document:

```tt
[%- sections.title = '.title' | ml -%]

[%- sections.head = BLOCK %]
    <style type="text/css"> .action-box { padding: 0 1em; } </style>
[% END -%]

<p>[% '.body.intro' | ml %]</p>
...page body...
```

`sections.title`, `sections.head`, `sections.windowtitle`, `sections.bodyopts`
are the common ones.

### Standalone (`no_sitescheme`) pages: full document

The template emits the entire document, including `<head>`:

```tt
<html>
<head>
<meta name="viewport" content="width = 320" />
<title>[% '.page.title' | ml %]</title>
</head>
<body>
...
</body>
</html>
```

### Translated strings

The `| ml` filter is the equivalent of BML's `$ML{'.key'}` / `BML::ml()`:

```tt
[% '.body.pending' | ml %]                            [%# no args %]
[% '.invite.from'  | ml( user => inv.mu.ljuser_display ) %]   [%# with args %]
```

Keys that start with `.` resolve **relative to this template's path** (its
"scope", e.g. `/manage/invites.tt`). Use a full path to reach another page's
string: `dw.ml('/some/other.tt.key')`.

There is also a function form, `dw.ml('.key', arg => …)`, used when the result is
an argument to something else (e.g. a `form.*` helper's `label`). Filter and
function forms are interchangeable.

### Helpers and methods

- **`dw.*`** — `dw.form_auth`, `dw.create_url(...)`, `dw.ml(...)`, `dw.need_res(...)`,
  `dw.active_resource_group('foundation')`.
- **`form.*`** — `form.textbox`, `form.password`, `form.textarea`, `form.select`,
  `form.checkbox`, `form.radio`, `form.submit`, `form.hidden`. These replace the
  old `LJ::html_*` builders.
- **`site.*`** — `site.root`, `site.imgroot`, `site.name`, `site.nameshort`, …
  (replaces `$LJ::SITEROOT`, `$LJ::SITENAMESHORT`, etc.).
- **Object methods** are called directly: `u.ljuser_display`, `u.name_html`,
  `u.is_community`, etc.

### Control flow

```tt
[% IF errors.exist %] … [% ELSIF invites.size %] … [% ELSE %] … [% END %]
[% FOREACH inv IN invites %] … [% loop.index %] / [% loop.count %] … [% END %]
```

### Forms

Always emit the CSRF token inside a POST form, and pair it with `form_auth => 1`
on the controller:

```tt
<form method="post" action="[% site.root %]/mobile/login">
  [% dw.form_auth %]
  ...
</form>
```

---

## 4. Translation strings (`.text`)

The `.text` file format is unchanged: `.key=value`, one per stanza, with
`[[placeholder]]` interpolation.

**Preserve history with `git mv`** when the conversion is 1:1:

```bash
git mv htdocs/mobile/login.bml.text views/mobile/login.tt.text
```

If you are restructuring (splitting a page, renaming many keys), it's fine to
delete the old file and write a fresh one instead.

### Repointing cross-file references (mandatory)

Find every other file that referenced the old keys by full path and repoint them
to the new `.tt` keys — otherwise those pages break:

```bash
grep -rn "/mobile/login.bml" --include='*.tt' --include='*.pm' .
```

```diff
- text = dw.ml( '/manage/invites.bml.title2' )
+ text = dw.ml( '/manage/invites.tt.title' )
```

### Retiring old keys in `deadphrases.dat` (recommended)

`bin/upgrading/texttool.pl load` is **purely additive** — it never deletes keys
that disappear from source. The *only* thing that removes an old key from the
production translation database is an entry in `bin/upgrading/deadphrases.dat`.
So when you delete `foo.bml.text`, its `/foo.bml.*` keys are orphaned in
production forever unless you list them:

```
general /mobile/login.bml.form.button
general /mobile/login.bml.form.password
...
```

This is best-effort cleanup (production-only; skipped on dev servers) and is
applied inconsistently across historical commits — but listing the removed keys
is the recommended practice. The *mandatory* step is repointing cross-file
references (above); deadphrasing is the *tidy* step.

> **The single most common conversion bug:** full-path keys in Perl, relative
> keys in templates. In a controller, `error_ml`/`LJ::Lang::ml` resolve
> immediately, so they need the **full path** (`'/foo.tt.error.x'`). In a
> template, `'.key' | ml` resolves **relative** to the current template.
> `DW::FormErrors` keys are the exception — they resolve at *render* time, so
> relative `.key` codes work from the controller (see below).

---

## 5. Errors and messages

There are three distinct mechanisms; pick by situation.

### (a) Whole-page error/success — `error_ml` / `success_ml`

Early-return helpers that render the generic `error.tt` / `success.tt`. Because
they resolve the string in the controller, **use full-path keys**:

```perl
return error_ml('/register.tt.error.usernonexistent');
return success_ml( '/register.tt.success.sent', { email => $u->email_raw } );
```

`render_success(...)` is a variant that renders `success-page.tt` with a `scope`,
so *its* `.success.message` / `.success.title` keys resolve page-relative.

### (b) Field/page validation with input preserved — `DW::FormErrors`

The workhorse for forms. Collect errors, then **re-render the same template**
(POST-then-render):

```perl
use DW::FormErrors;
my $errors = DW::FormErrors->new;

$errors->add( 'user', '.login.invalid_username' ) unless $u;   # field error
$errors->add( '',     '.login.ip_banned' )        if $banned;  # page-level (no field)

if ( $errors->exist ) {
    $rv->{errors} = $errors;
    return DW::Template->render_template( 'foo.tt', $rv );
}
```

`DW::FormErrors` keys resolve at render time against the template scope, so
relative `.key` codes are correct here. In a sitescheme template, render them
with the shared components:

```tt
[% INCLUDE components/errors.tt errors = errors %]                   [%# page-level list %]
[% INCLUDE components/error.tt error_name = 'email' errors = errors %] [%# inline, one field %]
```

> `components/errors.tt` emits Foundation `alert-box` markup. On a
> **`no_sitescheme`** page (no Foundation CSS) render errors yourself instead:
>
> ```tt
> [%- IF errors.exist %]
> <p class="error">[% FOREACH err IN errors.get_all %][% err.message %]<br />[% END %]</p>
> [%- END %]
> ```

### (c) Foundation flash banners — `$r->add_msg`

For success/warning banners that the site skin renders automatically (no template
plumbing). Sitescheme pages only:

```perl
$r->add_msg( LJ::Lang::ml('/foo.tt.success'), $r->SUCCESS );  # also ->ERROR, ->WARNING
```

---

## 6. authas, specify_user, GET args

`controller( authas => 1 )` loads the managed account into `$rv->{u}` (while
`$rv->{remote}` stays the viewer) and provides two renderings:

- **`authas_form`** (preferred, Foundation) — a complete `<form>`; just print it:
  ```tt
  [%- authas_form -%]
  ```
- **`authas_html`** (legacy) — only the `<select>`; you wrap your own GET form:
  ```tt
  <form method="get">[%- authas_html -%]</form>
  ```

`controller( authas => { showall => 1 } )` forwards extra args into the switcher.

For arbitrary query args, read them directly — `$r->get_args->{foo}`. (The
declarative `specify_user => 1` option exists but is rarely used in practice.)

---

## 7. Redirects and route cleanup

Some BML pages had hard-coded routes/redirects in `cgi-bin/Apache/LiveJournal.pm`.
When converting such a page, remove the old entry and reimplement it in the
controller:

```diff
- # confirm
- if ( $uri =~ m!^/confirm/(\w+\.\w+)! ) {
-     return redir( $apache_r, "$LJ::SITEROOT/register.bml?$1" );
- }
```

```perl
DW::Routing->register_regex( '^/confirm/(\w+\.\w+)', \&confirm_handler, app => 1 );
sub confirm_handler {
    my ( $opts, $auth_string ) = @_;
    return DW::Request->get->redirect("/register?$auth_string");
}
```

Most pages, though, are served purely by BML auto-routing (the `.bml` path *is*
the URL) and need no `Apache/LiveJournal.pm` change — just the `register_string`
in the new controller.

---

## 8. CSS

Judgment call, not a rule:

- **Inline** small, page-specific styling into a `sections.head` BLOCK (sitescheme)
  or the document `<head>` (standalone). This is right for a dozen lines of
  page-local CSS.
- **Keep/move to a `.css` file** loaded via `dw.need_res(...)` when the styling is
  substantial, shared across pages, or already a component stylesheet:
  ```tt
  [%- dw.need_res( { group => "foundation" } "stc/css/components/tables-as-list.css" ) -%]
  ```

---

## 9. BML → TT cheatsheet

| BML | TT / controller |
|-----|-----------------|
| `<?page title=>… body<= … <=body page?>` | `sections.title` + template body |
| `<?_code … _code?>` (logic) | the controller `.pm` |
| `return "<?needlogin?>"` | `controller( anonymous => 0 )` |
| `LJ::get_remote()` | `$rv->{remote}` |
| `LJ::did_post()` | `$r->did_post` |
| `LJ::check_form_auth()` | `form_auth => 1` (+ `[% dw.form_auth %]`) |
| `%POST` / `%GET` | `$r->post_args` / `$r->get_args` |
| `$ML{'.key'}` / `BML::ml('.key', {…})` | `'.key' \| ml` / `'.key' \| ml( a => … )` |
| `LJ::need_res('stc/x.css')` | inline `<style>`, or `dw.need_res(...)` |
| `LJ::ljuser($u)` string-building | `u.ljuser_display` |
| `BML::redirect(...)` | `$r->redirect(...)` |
| `$LJ::SITEROOT` | `site.root` |
| `$LJ::SITENAMESHORT` | `site.nameshort` |

---

## 10. Worked example: `/mobile/login`

A small standalone (`no_sitescheme`) page. Highlights every core pattern:

- **Standalone document** — the `.tt` emits its own `<html>`/`<head>`; the
  controller passes `{ no_sitescheme => 1 }`.
- **Anonymous + CSRF** — `controller( anonymous => 1, form_auth => 1 )` with
  `[% dw.form_auth %]` in the form (the original BML had no CSRF token; the
  conversion adds one).
- **`DW::FormErrors`** — invalid username / bad password / IP-ban each `->add`
  an error and re-render the form (the original printed a bare error string with
  no form). Errors are rendered with plain markup because there's no Foundation
  CSS on a standalone page.
- **Preserved behavior** — a plain GET while logged in logs the user out (the
  "log out" link on `/mobile/`); success redirects to `/mobile/?t=<time>`.
- **`git mv`** — `htdocs/mobile/login.bml.text` → `views/mobile/login.tt.text`,
  no content change.

See `cgi-bin/DW/Controller/Mobile/Login.pm` and `views/mobile/login.tt`.

---

## 11. Before you push

Run inside the devcontainer and fix any failures (CI runs these and fails the
build even for files you didn't touch):

```bash
perl extlib/bin/tidyall -a   # auto-format
perl t/02-tidy.t             # verify formatting
perl t/00-compile.t          # verify all modules compile
```

Templates (`.tt`) and `.text` files are not perltidy'd, but the controller `.pm`
must be tidy.

## 12. Testing it live

```bash
perl bin/starman --port 8080
```

Then exercise every path — GET, each validation failure, and the success
redirect — with `curl` (use a cookie jar and copy the `lj_form_auth` token from
the GET into your POST). Confirm the URL, the rendered strings, and (for forms)
the redirect/session behavior.
