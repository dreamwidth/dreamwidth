# dw-editor

The Dreamwidth rich text editor: a small, dependency-light WYSIWYG editor for
the entry form, built directly on [ProseMirror](https://prosemirror.net/)
(no framework, no wrapper library).

It edits a document that serializes to plain HTML plus Dreamwidth's special
tags (`<cut>`, `<user name=...>`), which is submitted through the normal
`#entry-body` textarea under the `rte1` markup format (see `DW::Formats`).
The server-side HTML cleaner remains the only sanitizer of record — the
editor's output is untrusted input like any other.

## Layout

| File | Purpose |
|---|---|
| `src/schema.js` | Document schema, including DW-specific nodes (`cut`, `user`, `html_block`) and the generic pieces that carry unmodeled markup (`extra` attributes, `html_textblock`, `html_container`, `html_mark`, `html_inline`) |
| `src/serialize.js` | HTML import/export: `<user>` tag balancing, the import pre-pass that preserves unknown markup, casual-HTML/Markdown conversion, raw-HTML block capture |
| `src/paste.js` | Pasted poll/embed markup becomes an HTML block; `insertRawBlock` |
| `src/nodeviews.js` | In-editor rendering for cut tags, user mentions, and HTML blocks |
| `src/mentions.js` | `@username` autocomplete (circle-scoped; see `/__rpc_general?mode=list_circle`) |
| `src/menu.js` | Toolbar |
| `src/dialogs.js` | Link/image/user insertion dialogs (native `<dialog>`) |
| `src/inputrules.js` | Markdown-style typing shortcuts (`**bold**`, `# heading`, `- list`, ...) |
| `src/keymap.js` | Keyboard shortcuts |
| `src/index.js` | Public API: `DWEditor.mount/unmount/isActive/getHTML/flush/isDirty/insertImage/insertHTMLBlock/focus` |

The page-side glue that swaps the editor in and out based on the format
`<select>` lives in `htdocs/js/pages/entry/editor.js`; the editor styles live
in `htdocs/scss/components/dw-editor.scss` (compiled to
`htdocs/stc/css/components/dw-editor.css` by `bin/build-static.sh`).

## Existing entries are never rewritten behind your back

Opening an entry must not drop markup the editor has no button for. On import
a pre-pass rewrites the parsed HTML so that `<span style>`, `<font>`,
`<center>`, `<div>`, `<a name>`, `class`/`style`/`id` attributes and the like
become generic nodes/marks (or literal HTML blocks for tables, polls, embeds and
elements with no model at all), and export puts them back. User tags inside
literal blocks are restored to the spelling they had. The round-trip tests in
`test/` pin this down: add a case there whenever you teach the editor a new kind
of markup.

An entry opened and saved without edits is stored byte-for-byte as it was; the
textarea is only rewritten once the document changes (or a format conversion
makes the old text meaningless).

## Format conversion

`mount(..., { fromFormat })` and `unmount(..., { toFormat })` make the
conversions between rich text and the plain formats explicit:

- Casual HTML (and the retired `rte0`, which the cleaner treats as casual HTML)
  becomes explicit markup on the way in: newlines become `<br>`, bare URLs
  become links, and `@name` mentions become user tags, matching what the server
  would have rendered. Markdown gets the line breaks and mentions; its other
  syntax can't be converted client-side (the page asks first).
- Leaving for casual HTML strips the cosmetic newlines the serializer adds, so
  the server's auto-line-breaking doesn't double them. Raw HTML and Markdown
  read the explicit HTML as it is.

## Tests

```bash
cd src/editor
npm ci
npm test        # node --test, with jsdom standing in for the browser
```

## Building

The built bundle is **checked in** at `htdocs/js/vendor/dw-editor.js` so the
site build needs no Node toolchain. After changing anything under `src/`,
rebuild and commit the bundle:

```bash
cd src/editor
npm ci
npm run build
```

Requires Node 18+. The bundle is unminified for reviewability;
`bin/build-static.sh --compress` minifies it for production along with all
other JS.
