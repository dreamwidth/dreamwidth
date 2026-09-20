// Public API for the Dreamwidth rich text editor, exposed as window.DWEditor.
//
// The editor mounts over an existing <textarea>, which stays in the form as
// the canonical field: the document is serialized back into it (debounced
// while typing, synchronously on submit), so drafts, preview, and the no-JS
// fallback all keep working unchanged.
//
//   DWEditor.mount("entry-body", { circleUrl, strings, onInput, ... })
//   DWEditor.unmount("entry-body")   // serializes back, restores the textarea
//   DWEditor.isActive("entry-body")
//   DWEditor.getHTML("entry-body")

import { EditorState } from "prosemirror-state";
import { EditorView } from "prosemirror-view";
import { history } from "prosemirror-history";
import { dropCursor } from "prosemirror-dropcursor";
import { gapCursor } from "prosemirror-gapcursor";

import { schema } from "./schema.js";
import { importHTML, exportHTML } from "./serialize.js";
import { buildNodeViews } from "./nodeviews.js";
import { mentionsPlugin } from "./mentions.js";
import { buildInputRules } from "./inputrules.js";
import { buildKeymap } from "./keymap.js";
import { buildToolbar } from "./menu.js";

const SYNC_DELAY = 400; // ms of typing quiet before syncing to the textarea

const DEFAULT_STRINGS = {
    toolbarLabel: "Formatting",
    undo: "Undo",
    redo: "Redo",
    blockLabel: "Paragraph style",
    blockParagraph: "Paragraph",
    blockHeading: "Heading",
    blockCode: "Code block",
    blockHtml: "HTML block",
    bold: "Bold",
    italic: "Italic",
    underline: "Underline",
    strike: "Strikethrough",
    codeMark: "Code",
    link: "Link",
    image: "Image",
    user: "User or community",
    bulletList: "Bulleted list",
    orderedList: "Numbered list",
    blockquote: "Quote",
    cut: "Cut tag",
    hr: "Horizontal line",
    outdent: "Unindent",
    cutEdit: "Edit",
    cutCaption: "Cut text",
    cutDefault: "Read more",
    htmlBlockLabel: "HTML (kept as-is)",
    cancel: "Cancel",
    ok: "OK",
    linkTitle: "Add link",
    linkUrl: "URL",
    imageTitle: "Add image",
    imageUrl: "Image URL",
    imageAlt: "Alt text",
    userTitle: "Link a user or community",
    userName: "Username",
    userSite: "Site",
    userSiteHint: "leave blank for this site",
    mentionLiteral: "use as typed",
    mentionCommunity: "community",
};

const instances = {};

// Casual-HTML and Markdown drafts carry meaningful plain newlines; explicit
// HTML doesn't. When mounting over such content, turn them into <br /> the
// same way the old FCK editor did on format switch.
function materializeLinebreaks(html) {
    return html.replace(/\r?\n/g, "<br />");
}

export function mount(id, opts) {
    if (instances[id]) return instances[id];
    opts = opts || {};

    const textarea = document.getElementById(id);
    if (!textarea) return null;

    const strings = Object.assign({}, DEFAULT_STRINGS, opts.strings || {});

    let html = textarea.value;
    if (opts.materializeLinebreaks) html = materializeLinebreaks(html);

    const toolbar = buildToolbar(schema, strings);

    const wrapper = document.createElement("div");
    wrapper.className = "dw-editor";
    wrapper.appendChild(toolbar.dom);
    textarea.parentNode.insertBefore(wrapper, textarea);
    textarea.style.display = "none";

    const state = EditorState.create({
        doc: importHTML(schema, html),
        plugins: [
            // Mentions first: its handleKeyDown must see Enter/Tab/arrows
            // before the keymaps do.
            mentionsPlugin({ circleUrl: opts.circleUrl, strings: strings }),
            buildInputRules(schema),
            ...buildKeymap(schema, toolbar.commands),
            history(),
            dropCursor(),
            gapCursor(),
        ],
    });

    let syncTimer = null;
    const instance = {
        view: null,
        textarea: textarea,
        wrapper: wrapper,
        sync() {
            if (syncTimer) {
                clearTimeout(syncTimer);
                syncTimer = null;
            }
            textarea.value = exportHTML(schema, instance.view.state.doc);
        },
        onSubmit: () => instance.sync(),
    };

    instance.view = new EditorView(wrapper, {
        state: state,
        nodeViews: buildNodeViews(strings),
        dispatchTransaction(tr) {
            const view = instance.view;
            view.updateState(view.state.apply(tr));
            toolbar.update(view);
            if (tr.docChanged) {
                if (syncTimer) clearTimeout(syncTimer);
                syncTimer = setTimeout(() => {
                    syncTimer = null;
                    textarea.value = exportHTML(schema, view.state.doc);
                    if (opts.onInput) opts.onInput();
                }, SYNC_DELAY);
            }
        },
    });
    toolbar.update(instance.view);

    // Make sure the textarea is current before any submit (including the
    // preview button, which posts the same form).
    if (textarea.form) textarea.form.addEventListener("submit", instance.onSubmit);

    instances[id] = instance;
    return instance;
}

export function unmount(id) {
    const instance = instances[id];
    if (!instance) return;

    instance.sync();
    if (instance.textarea.form)
        instance.textarea.form.removeEventListener("submit", instance.onSubmit);
    instance.view.destroy();
    instance.wrapper.remove();
    instance.textarea.style.display = "";
    delete instances[id];
}

export function isActive(id) {
    return !!instances[id];
}

export function getHTML(id) {
    const instance = instances[id];
    if (!instance) return null;
    return exportHTML(schema, instance.view.state.doc);
}
