// Public API for the Dreamwidth rich text editor, exposed as window.DWEditor.
//
// The editor mounts over an existing <textarea>, which stays in the form as
// the canonical field: the document is serialized back into it (debounced
// while typing, synchronously on submit), so drafts, preview, and the no-JS
// fallback all keep working unchanged.
//
//   DWEditor.mount("entry-body", { circleUrl, strings, onInput, ... })
//   DWEditor.unmount("entry-body", { toFormat })  // serializes back, restores the textarea
//   DWEditor.isActive("entry-body")
//   DWEditor.getHTML("entry-body")
//   DWEditor.flush("entry-body")      // write the document to the textarea now
//   DWEditor.isDirty("entry-body")    // edited since mount (or markClean)?
//   DWEditor.insertImage("entry-body", { src, alt })
//   DWEditor.insertHTMLBlock("entry-body", html)
//   DWEditor.focus("entry-body")

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
import { trailingNode, appendTrailingParagraph } from "./trailingnode.js";
import { pastePlugin, insertRawBlock } from "./paste.js";

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
    poll: "Create a poll",
    embed: "Embed media",
    embedTitle: "Embed media",
    embedCode: "Paste the embed code",
};

const instances = {};

// Formats whose source the server auto-formats. Casual HTML turns newlines
// into <br /> and links bare URLs, and it and Markdown turn @name into a user
// tag; the retired rte0 format has no cleaner of its own and is cleaned as
// casual HTML. rte1 does none of that, so converting one of these to rich text
// has to do it up front (see serialize.js), and converting back has to leave
// no source newlines for the server to turn into extra line breaks.
const CASUAL_FORMATS = { html_casual1: 1, html_casual0: 1, rte0: 1 };
const MENTION_FORMATS = { html_casual1: 1, markdown0: 1, rte0: 1 };
const NEWLINE_FORMATS = { html_casual1: 1, html_casual0: 1, rte0: 1, markdown0: 1 };

function casualOptions(fromFormat, sites) {
    if (!NEWLINE_FORMATS[fromFormat]) return null;
    return {
        links: !!CASUAL_FORMATS[fromFormat],
        mentions: !!MENTION_FORMATS[fromFormat],
        sites: sites,
    };
}

// Put an inline node (an image) at the selection, or after the current block
// if the selection is somewhere inline content can't go (a code block).
function insertInline(view, node) {
    const { $from } = view.state.selection;
    if ($from.parent.type.spec.code) {
        const para = view.state.schema.nodes.paragraph.create(null, node);
        view.dispatch(view.state.tr.insert($from.after(), para).scrollIntoView());
    } else {
        view.dispatch(view.state.tr.replaceSelectionWith(node, false).scrollIntoView());
    }
    view.focus();
}

export function mount(id, opts) {
    if (instances[id]) return instances[id];
    opts = opts || {};

    const textarea = document.getElementById(id);
    if (!textarea) return null;

    const strings = Object.assign({}, DEFAULT_STRINGS, opts.strings || {});
    const sites = opts.icons && opts.icons.sites ? Object.keys(opts.icons.sites) : [];

    // Converting out of a casual format rewrites the source, so the textarea
    // can no longer be trusted to mean the same thing until we write it back.
    const casual = casualOptions(opts.fromFormat, sites);

    const toolbar = buildToolbar(schema, strings, {
        onImage: opts.onImage,
        pollUrl: opts.pollUrl,
        canEmbed: !!opts.canEmbed,
    });

    const wrapper = document.createElement("div");
    wrapper.className = "dw-editor";
    wrapper.appendChild(toolbar.dom);
    textarea.parentNode.insertBefore(wrapper, textarea);
    textarea.style.display = "none";

    const state = EditorState.create({
        doc: importHTML(schema, textarea.value, { casual: casual }),
        plugins: [
            // Mentions first: its handleKeyDown must see Enter/Tab/arrows
            // before the keymaps do.
            mentionsPlugin({
                circleUrl: opts.circleUrl,
                strings: strings,
                sites: sites,
            }),
            buildInputRules(schema),
            ...buildKeymap(schema, toolbar.commands),
            history(),
            dropCursor(),
            gapCursor(),
            trailingNode(),
            pastePlugin(),
        ],
    });

    let syncTimer = null;
    const instance = {
        view: null,
        textarea: textarea,
        wrapper: wrapper,
        fromFormat: opts.fromFormat || "",
        // edited: the poster changed the document. stale: the textarea
        // doesn't reflect the document (we converted it, or they edited).
        edited: false,
        stale: !!casual,
        // Write the document into the textarea. Skipped while the textarea
        // already says the same thing, so an entry opened and saved without
        // edits is stored byte-for-byte as it was.
        sync(force, exportOpts) {
            if (syncTimer) {
                clearTimeout(syncTimer);
                syncTimer = null;
            }
            if (!instance.stale && !force) return;
            textarea.value = exportHTML(schema, instance.view.state.doc, exportOpts);
            instance.stale = false;
        },
        onSubmit: () => instance.sync(),
    };

    instance.view = new EditorView(wrapper, {
        state: state,
        nodeViews: buildNodeViews({ strings: strings, icons: opts.icons }),
        dispatchTransaction(tr) {
            const view = instance.view;
            view.updateState(view.state.apply(tr));
            toolbar.update(view);
            if (tr.docChanged && !tr.getMeta("dwSeed")) {
                instance.edited = true;
                instance.stale = true;

                // Serializing the whole document is the expensive part, so
                // that's what waits for a pause. The draft scheduler gets
                // told about every change (it does its own debouncing, and
                // reads the document on demand via getHTML), otherwise
                // continuous typing would starve autosave.
                if (syncTimer) clearTimeout(syncTimer);
                syncTimer = setTimeout(() => instance.sync(), SYNC_DELAY);
                if (opts.onInput) opts.onInput();
            }
        },
    });
    toolbar.update(instance.view);

    // If the imported entry already ends in a cut (or other non-paragraph
    // block), seed the trailing paragraph now -- the plugin above only runs on
    // edits, so without this you'd be unable to click below it.
    const seed = appendTrailingParagraph(instance.view.state);
    if (seed) {
        seed.setMeta("addToHistory", false);
        seed.setMeta("dwSeed", true);
        instance.view.dispatch(seed);
    }

    // Make sure the textarea is current before the form leaves the page. The
    // submit event covers the buttons; the preview and login-modal paths call
    // form.submit() directly, which fires no event, so that is wrapped too.
    const form = textarea.form;
    if (form) {
        form.addEventListener("submit", instance.onSubmit, true);
        if (typeof form.submit == "function") {
            const nativeSubmit = form.submit;
            form.submit = function () {
                instance.sync();
                return nativeSubmit.apply(form, arguments);
            };
            instance.restoreSubmit = () => {
                delete form.submit;
            };
        }
    }

    instances[id] = instance;
    return instance;
}

// opts.toFormat: the format the entry is switching to. Leaving for a casual
// format needs newline-free output (see exportHTML); leaving for a different
// format than we were loaded from always rewrites the textarea.
export function unmount(id, opts) {
    const instance = instances[id];
    if (!instance) return;

    opts = opts || {};
    const toFormat = opts.toFormat || "";
    instance.sync(!!toFormat && toFormat != instance.fromFormat, {
        flatten: !!(CASUAL_FORMATS[toFormat] && toFormat != "rte0"),
    });
    if (instance.textarea.form) {
        instance.textarea.form.removeEventListener("submit", instance.onSubmit, true);
        if (instance.restoreSubmit) instance.restoreSubmit();
    }
    instance.view.destroy();
    instance.wrapper.remove();
    instance.textarea.style.display = "";
    delete instances[id];
}

export function isActive(id) {
    return !!instances[id];
}

// Write the document to its textarea right now (used before any programmatic
// form submission).
export function flush(id) {
    const instance = instances[id];
    if (instance) instance.sync();
}

export function isDirty(id) {
    const instance = instances[id];
    return !!instance && instance.edited;
}

export function insertImage(id, values) {
    const instance = instances[id];
    if (!instance || !values || !values.src) return false;
    insertInline(
        instance.view,
        schema.nodes.image.create({ src: values.src, alt: values.alt || "" })
    );
    return true;
}

export function insertHTMLBlock(id, html) {
    const instance = instances[id];
    if (!instance) return false;
    insertRawBlock(instance.view, html || "");
    return true;
}

export function focus(id) {
    const instance = instances[id];
    if (instance) instance.view.focus();
}

export function getHTML(id) {
    const instance = instances[id];
    if (!instance) return null;
    return exportHTML(schema, instance.view.state.doc);
}
