// HTML import/export for the Dreamwidth rich text editor.
//
// Import: stored entry HTML -> ProseMirror document. Two wrinkles:
//   1. Dreamwidth's <user name="..."> tag is conventionally unclosed, so the
//      browser parser would swallow everything after it as children. We
//      rewrite it to a balanced <dw-user> placeholder first.
//   2. Block markup the schema doesn't model (tables, polls, embeds, ...) is
//      captured verbatim into <dw-html-block> wrappers, which parse into
//      editable literal-HTML blocks instead of being mangled or dropped.
//
// Export: ProseMirror document -> HTML string. html_block nodes are emitted
// verbatim via placeholder substitution (DOMSerializer alone can't emit raw
// markup), and </user> close tags are stripped to match site convention.

import { DOMParser as PMDOMParser, DOMSerializer } from "prosemirror-model";

// Block-level markup we preserve as literal HTML rather than parse lossily.
// Dreamwidth's own block tags are here too: polls and embeds round-trip as
// source until they grow dedicated nodes.
const CAPTURE_SELECTOR = [
    "table",
    "form",
    "iframe",
    "object",
    "embed",
    "style",
    "textarea",
    "select",
    "input",
    "button",
    "details",
    "audio",
    "video",
    "poll",
    "lj-poll",
    "site-embed",
    "lj-embed",
    "lj-raw",
    "raw-code",
].join(", ");

function captureUnsupportedBlocks(root) {
    const found = root.querySelectorAll(CAPTURE_SELECTOR);
    for (let i = 0; i < found.length; i++) {
        const el = found[i];
        // Document order guarantees ancestors come first, so anything no
        // longer attached was already captured inside an earlier match.
        if (!root.contains(el)) continue;
        const block = document.createElement("dw-html-block");
        block.textContent = el.outerHTML;
        el.replaceWith(block);
    }
}

// Rewrite DW user tags into balanced placeholder elements the browser can
// parse without swallowing trailing content. Handles <user name= >,
// <lj user= >, <lj comm= >, optional self-closing slashes, and stray close
// tags. The lookahead keeps <lj-cut> etc. from matching.
function balanceUserTags(html) {
    return html
        .replace(/<\/(?:lj|user)>/gi, "")
        .replace(/<(?:user|lj)(?=[\s/>])([^>]*?)\/?>/gi, "<dw-user$1></dw-user>");
}

export function importHTML(schema, html) {
    const tpl = document.createElement("template");
    tpl.innerHTML = balanceUserTags(String(html == null ? "" : html));
    captureUnsupportedBlocks(tpl.content);
    return PMDOMParser.fromSchema(schema).parse(tpl.content);
}

function buildSerializer(schema, rawChunks) {
    const nodes = DOMSerializer.nodesFromSchema(schema);
    nodes.html_block = (node) => {
        const el = document.createElement("dw-raw-placeholder");
        el.setAttribute("data-key", String(rawChunks.push(node.textContent) - 1));
        return el;
    };
    return new DOMSerializer(nodes, DOMSerializer.marksFromSchema(schema));
}

export function exportHTML(schema, doc) {
    // An empty document is a single empty paragraph; submit it as nothing.
    if (
        doc.childCount == 1 &&
        doc.firstChild.type.name == "paragraph" &&
        doc.firstChild.content.size == 0
    )
        return "";

    const rawChunks = [];
    const serializer = buildSerializer(schema, rawChunks);

    // Serialize each top-level block on its own line, for readable source if
    // the entry is later opened in raw HTML mode. rte1 never adds automatic
    // linebreaks, so the whitespace is cosmetic.
    const parts = [];
    doc.content.forEach((child) => {
        const div = document.createElement("div");
        div.appendChild(serializer.serializeNode(child, { document }));

        // Swap raw-HTML placeholders for markers that survive innerHTML
        // escaping, then substitute the literal chunks back in.
        div.querySelectorAll("dw-raw-placeholder").forEach((ph) => {
            ph.replaceWith(
                document.createTextNode("\u0001DWRAW" + ph.getAttribute("data-key") + "\u0001")
            );
        });
        parts.push(
            div.innerHTML.replace(/\u0001DWRAW(\d+)\u0001/g, (m, key) => rawChunks[+key])
        );
    });

    // <user> is conventionally unclosed in DW markup.
    return parts.join("\n\n").replace(/<\/user>/g, "");
}
