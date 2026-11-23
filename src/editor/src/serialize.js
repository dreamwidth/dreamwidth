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

// Unwrap a list item's lone, attribute-less <p> so it renders tight. Only the
// single-child case is touched, so multi-paragraph items aren't merged.
function unwrapTightListItems(root) {
    root.querySelectorAll("li").forEach((li) => {
        const only = li.children.length == 1 ? li.firstElementChild : null;
        if (only && only.tagName == "P" && only.attributes.length == 0) {
            while (only.firstChild) li.insertBefore(only.firstChild, only);
            li.removeChild(only);
        }
    });
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
    // Collect the top-level blocks, dropping a trailing empty paragraph: the
    // editor keeps one after block containers (cuts, lists, ...) so you can
    // always type past them, but it's an editing affordance, not content.
    const children = [];
    doc.content.forEach((child) => children.push(child));
    while (
        children.length > 1 &&
        children[children.length - 1].type.name == "paragraph" &&
        children[children.length - 1].content.size == 0
    )
        children.pop();

    // An empty document is a single empty paragraph; submit it as nothing.
    if (
        children.length == 1 &&
        children[0].type.name == "paragraph" &&
        children[0].content.size == 0
    )
        return "";

    const rawChunks = [];
    const serializer = buildSerializer(schema, rawChunks);

    // Serialize each top-level block on its own line, for readable source if
    // the entry is later opened in raw HTML mode. rte1 never adds automatic
    // linebreaks, so the whitespace is cosmetic.
    const parts = [];
    children.forEach((child) => {
        const div = document.createElement("div");
        div.appendChild(serializer.serializeNode(child, { document }));

        // List items serialize as <li><p>text</p></li>, but a block <p> inside
        // an <li> makes the browser drop the marker onto its own line with the
        // text below it. For the common single-paragraph item, unwrap the <p>
        // so it renders "tight" (<li>text</li>) -- matching what the editor
        // shows. Multi-block items keep their <p>s (they're genuinely loose).
        unwrapTightListItems(div);

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
