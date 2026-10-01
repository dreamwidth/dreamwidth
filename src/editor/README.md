# dw-editor

The Dreamwidth rich text editor: a small, dependency-light WYSIWYG editor for
the beta entry form, built directly on [ProseMirror](https://prosemirror.net/)
(no framework, no wrapper library).

It edits a document that serializes to plain HTML plus Dreamwidth's special
tags (`<cut>`, `<user name=...>`), which is submitted through the normal
`#entry-body` textarea under the `rte1` markup format (see `DW::Formats`).
The server-side HTML cleaner remains the only sanitizer of record — the
editor's output is untrusted input like any other.

## Layout

| File | Purpose |
|---|---|
| `src/schema.js` | Document schema, including DW-specific nodes: `cut`, `user`, `html_block` |
| `src/serialize.js` | HTML import/export, incl. `<user>` tag balancing and raw-HTML block capture |
| `src/nodeviews.js` | In-editor rendering for cut tags, user mentions, and HTML blocks |
| `src/mentions.js` | `@username` autocomplete (circle-scoped; see `/__rpc_general?mode=list_circle`) |
| `src/menu.js` | Toolbar |
| `src/dialogs.js` | Link/image/user insertion dialogs (native `<dialog>`) |
| `src/inputrules.js` | Markdown-style typing shortcuts (`**bold**`, `# heading`, `- list`, ...) |
| `src/keymap.js` | Keyboard shortcuts |
| `src/index.js` | Public API: `DWEditor.mount/unmount/isActive/getHTML` |

The page-side glue that swaps the editor in and out based on the format
`<select>` lives in `htdocs/js/pages/entry/editor.js`; the editor styles live
in `htdocs/stc/css/components/dw-editor.css`.

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
