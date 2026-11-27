// src/editor/src/serialize.js
//
// HTML import/export for the Dreamwidth rich text editor.
//
// Import: stored entry HTML -> ProseMirror document. The browser's parser
// builds a DOM, then a pre-pass rewrites it so that nothing the schema can't
// model is lost:
//   1. Dreamwidth's <user name="..."> tag is conventionally unclosed, so the
//      browser parser would swallow everything after it as children. We
//      rewrite it to a balanced <dw-user> placeholder first (remembering
//      whether it was spelled <user> or <lj>).
//   2. Block markup the schema doesn't model (polls, embeds, tables the table
//      nodes can't hold exactly, ...) and any element we have no model for is
//      captured verbatim: as a <dw-html-block> (an editable literal-HTML
//      block), or as a <dw-raw-inline> when it sits inside running text.
//   3. <div>, <center>, <span>, <font>, <small>, <a name>, ... become
//      <dw-block>/<dw-textblock>/<dw-inline> placeholders that remember the
//      original tag and attributes; every other attribute the schema doesn't
//      model (class, style, id, align, ...) is stashed in data-dw-x.
//
// Export: ProseMirror document -> HTML string. Raw chunks are emitted verbatim
// via placeholder substitution (DOMSerializer alone can't emit raw markup),
// and </user> close tags are stripped to match site convention.
//
// A load -> export round trip is meant to be lossless for anything the user
// didn't touch. "Lossless" is semantic: whitespace is normalized, <b>/<i>
// become <strong>/<em>, and loose top-level text gets wrapped in <p>.
//
// Authors:
//     Mark Smith <mark@qq.is>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself.  For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

import { DOMParser as PMDOMParser, DOMSerializer } from "prosemirror-model";
import { render, GENERIC_BLOCK_TAGS, GENERIC_INLINE_TAGS } from "./schema.js";
import { textStyleFromCSS } from "./style.js";

// Block-level markup we preserve as literal HTML rather than parse lossily.
// Dreamwidth's own block tags are here too: polls and embeds round-trip as
// source until they grow dedicated nodes.
const RAW_BLOCK_TAGS = new Set([
    "table",
    "form",
    "iframe",
    "object",
    "embed",
    "style",
    "script",
    "noscript",
    "textarea",
    "select",
    "input",
    "button",
    "details",
    "audio",
    "video",
    "canvas",
    "svg",
    "math",
    "map",
    "dl",
    "fieldset",
    "marquee",
    "poll",
    "lj-poll",
    "site-embed",
    "lj-embed",
    "lj-raw",
    "raw-code",
]);

const KNOWN_BLOCK_TAGS = new Set([
    "p",
    "blockquote",
    "hr",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "pre",
    "ol",
    "ul",
    "li",
    "cut",
    "lj-cut",
]);

const GENERIC_BLOCK = new Set(GENERIC_BLOCK_TAGS);

// Inline marks the schema models directly; with attributes they become
// generic html_marks instead so the attributes survive.
const MODELED_MARK_TAGS = new Set([
    "em",
    "i",
    "strong",
    "b",
    "u",
    "s",
    "strike",
    "code",
    "sub",
    "sup",
]);

const BLOCKISH = new Set([...KNOWN_BLOCK_TAGS, ...GENERIC_BLOCK_TAGS, ...RAW_BLOCK_TAGS]);
const BLOCKISH_SELECTOR = Array.from(BLOCKISH).join(",");

// Parents inside which an unmodeled element is part of running text.
const INLINE_PARENTS = new Set([
    ...GENERIC_INLINE_TAGS,
    "p",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "li",
    "a",
    "dw-textblock",
    "dw-inline",
    "dw-style",
    "dw-user",
]);

const ATTR_NAME = /^[a-zA-Z_:][-a-zA-Z0-9_:.]*$/;

// Rewrite DW user tags into balanced placeholder elements the browser can
// parse without swallowing trailing content. Handles <user name= >,
// <lj user= >, <lj comm= >, optional self-closing slashes, and stray close
// tags. The lookahead keeps <lj-cut> etc. from matching. The original tag
// name rides along so restoreUserTags can undo this inside raw chunks.
function balanceUserTags(html) {
    return html
        .replace(/<\/(?:lj|user)>/gi, "")
        .replace(
            /<(user|lj)(?=[\s/>])([^>]*?)\/?>/gi,
            (m, tag, attrs) => '<dw-user data-dw-tag="' + tag.toLowerCase() + '"' + attrs + "></dw-user>"
        );
}

// A posted poll is stored as a placeholder tag, <poll-123>, which is never
// closed (LJ::Poll expands it, matching exactly this spelling). A browser
// would take it for an element still open and put everything after it inside,
// so it's swapped for a closed placeholder before parsing.
function balancePollTags(html) {
    return html.replace(
        /<((?:lj-)?poll-\d+)>/g,
        (m, tag) => '<dw-poll-ref data-dw-tag="' + tag + '"></dw-poll-ref>'
    );
}

// ---- Cut tags ------------------------------------------------------------
//
// A cut can start in the middle of a paragraph and end paragraphs later:
//
//     <p>Visible, and then <cut text="More">hidden.</p><p>Also hidden.</p></cut>
//
// The site handles that (its cleaner reads tags, not a tree), but a browser
// would close the cut at the first </p> and leave the rest of the hidden text
// out in the open. So each cut tag is swapped for an empty marker element
// before parsing, and the markers are paired up afterwards; the range between
// them becomes the cut, splitting the paragraphs it starts and ends in.
//
// In the editor a cut is a box. One that starts partway through a paragraph
// is "lead"-joined to the paragraph before it (the visible start), and one
// that ends partway through is "tail"-joined to the paragraph after it (the
// visible rest). exportHTML joins them back up.

const CUT_TAG = /<!--[\s\S]*?-->|<(script|style|textarea|xmp|title)\b[\s\S]*?<\/\1\s*>|<(\/?)(lj-)?cut((?:\s+[^\s=>/]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?)*)\s*\/?>/gi;

function markCutTags(html) {
    return html.replace(CUT_TAG, (m, raw, close, lj, attrs) => {
        if (raw || m.indexOf("<!--") == 0) return m;
        const tag = (lj || "") + "cut";
        if (close) return '<dw-cut-close data-dw-tag="' + tag + '"></dw-cut-close>';
        return (
            '<dw-cut-open data-dw-tag="' +
            tag +
            '" data-dw-attrs="' +
            attrs.replace(/&/g, "&amp;").replace(/"/g, "&quot;") +
            '"></dw-cut-open>'
        );
    });
}

function isParagraph(node) {
    return !!node && node.nodeType == 1 && node.localName == "p";
}

// Anything a reader would see: text that isn't just whitespace, or an element.
function hasContent(node) {
    return Array.from(node.childNodes).some((child) =>
        child.nodeType == 1 ? true : child.nodeType == 3 && /\S/.test(child.data)
    );
}

// Whether a paragraph's text ends (or starts) with whitespace. The editor
// trims a paragraph's edges, so a join point's space is kept on the cut.
function edgeSpace(el, atEnd) {
    return (atEnd ? /\s$/ : /^\s/).test(el.textContent);
}

function setJoin(cut, side, para) {
    cut.setAttribute("data-dw-" + side, edgeSpace(para, side == "lead") ? "space" : "1");
}

// The child of `ancestor` that `node` is inside.
function childOf(ancestor, node) {
    while (node && node.parentNode != ancestor) node = node.parentNode;
    return node;
}

function cutFromMarker(marker) {
    const tpl = document.createElement("template");
    tpl.innerHTML = "<" + marker.getAttribute("data-dw-tag") + marker.getAttribute("data-dw-attrs") + ">";
    const parsed = tpl.content.firstChild;
    const cut = document.createElement("cut");
    if (parsed && parsed.nodeType == 1)
        Array.from(parsed.attributes).forEach((a) => {
            if (a.name.indexOf("data-dw-") != 0) cut.setAttribute(a.name, a.value);
        });
    return cut;
}

// Turn each open/close marker pair into a <cut> around what's between them.
// An open without a close runs to the end (as the site treats it); a close
// without an open is dropped.
function pairCutMarkers(root) {
    const pairs = [];
    const stack = [];
    root.querySelectorAll("dw-cut-open, dw-cut-close").forEach((m) => {
        if (m.localName == "dw-cut-open") stack.push(m);
        else if (stack.length) pairs.push([stack.pop(), m]);
        else m.remove();
    });
    while (stack.length) {
        const end = document.createElement("dw-cut-close");
        root.appendChild(end);
        pairs.push([stack.pop(), end]);
    }

    // Inner cuts first, so each range holds whole cuts by the time it's taken.
    pairs.forEach(([open, close]) => {
        const cut = cutFromMarker(open);
        const range = document.createRange();
        range.setStartAfter(open);
        range.setEndBefore(close);
        const ancestor = range.commonAncestorContainer;
        const contents = range.extractContents();
        cut.appendChild(contents);

        if (open.parentNode == close.parentNode) {
            open.replaceWith(cut);
            close.remove();
            return;
        }

        // The cut crossed element boundaries, so it goes between the pieces
        // it split, as a sibling of them.
        const before = childOf(ancestor, open);
        const after = childOf(ancestor, close);
        ancestor.insertBefore(cut, before.nextSibling);
        open.remove();
        close.remove();
        if (isParagraph(before)) {
            if (hasContent(before)) setJoin(cut, "lead", before);
            else before.remove();
        }
        if (after && isParagraph(after)) {
            if (hasContent(after)) setJoin(cut, "tail", after);
            else after.remove();
        }
        // The pieces of those paragraphs inside the cut that hold nothing.
        [cut.firstChild, cut.lastChild].forEach((piece) => {
            if (isParagraph(piece) && !hasContent(piece) && cut.childNodes.length > 1) piece.remove();
        });
    });
}

// A cut found inside a paragraph (or in a run of loose text) is lifted out of
// it: the text before becomes the lead paragraph, the text after the tail.
function liftCut(cut) {
    const parent = cut.parentNode;
    if (isParagraph(parent)) {
        const tail = parent.cloneNode(false);
        while (cut.nextSibling) tail.appendChild(cut.nextSibling);
        parent.after(cut);
        cut.after(tail);
        if (hasContent(parent)) setJoin(cut, "lead", parent);
        else parent.remove();
        if (hasContent(tail)) setJoin(cut, "tail", tail);
        else tail.remove();
        return;
    }
    // Loose text beside it (an entry with no <p>s): gather the runs of inline
    // content on each side into paragraphs. Already-joined cuts keep theirs.
    if (cut.hasAttribute("data-dw-lead") || cut.hasAttribute("data-dw-tail")) return;
    const run = (step) => {
        const nodes = [];
        for (let n = cut[step]; n && !isBlockish(n); n = n[step]) nodes.push(n);
        return nodes;
    };
    const before = run("previousSibling").reverse();
    const after = run("nextSibling");
    const wrap = (nodes) => {
        const p = document.createElement("p");
        nodes[0].before(p);
        nodes.forEach((n) => p.appendChild(n));
        return hasContent(p) ? p : (p.replaceWith(...p.childNodes), null);
    };
    const lead = before.length && wrap(before);
    const tail = after.length && wrap(after);
    if (lead) setJoin(cut, "lead", lead);
    if (tail) setJoin(cut, "tail", tail);
}

// Undo balanceUserTags and balancePollTags for markup captured as a raw
// chunk, so a <user> tag or poll placeholder inside a preserved table comes
// back out exactly as written.
function restoreUserTags(html) {
    return html
        .replace(
            /<dw-user data-dw-tag="(user|lj)"([^>]*)><\/dw-user>/g,
            (m, tag, attrs) => "<" + tag + attrs + ">"
        )
        .replace(
            /<dw-poll-ref data-dw-tag="((?:lj-)?poll-\d+)"><\/dw-poll-ref>/g,
            (m, tag) => "<" + tag + ">"
        );
}

function rawBlock(html) {
    const block = document.createElement("dw-html-block");
    block.textContent = html;
    return block;
}

function rawInline(html) {
    const span = document.createElement("dw-raw-inline");
    span.setAttribute("data-html", html);
    return span;
}

function isBlockish(node) {
    if (node.nodeType != 1) return false;
    const tag = node.localName;
    if (BLOCKISH.has(tag)) return true;
    return (
        tag.indexOf("dw-") == 0 &&
        tag != "dw-user" &&
        tag != "dw-inline" &&
        tag != "dw-style" &&
        tag != "dw-raw-inline"
    );
}

function validAttrs(el) {
    for (let i = 0; i < el.attributes.length; i++)
        if (!ATTR_NAME.test(el.attributes[i].name)) return false;
    return true;
}

function allAttrs(el) {
    const extra = {};
    for (let i = 0; i < el.attributes.length; i++)
        extra[el.attributes[i].name] = el.attributes[i].value;
    return extra;
}

// Move every attribute the schema doesn't model into data-dw-x, and off the
// element, so the parser's own style/attribute rules never see them.
function stashAttrs(el, modeled) {
    const extra = {};
    Array.from(el.attributes).forEach((attr) => {
        if (modeled.indexOf(attr.name) >= 0) return;
        extra[attr.name] = attr.value;
        el.removeAttribute(attr.name);
    });
    if (Object.keys(extra).length) el.setAttribute("data-dw-x", JSON.stringify(extra));
}

function isEmpty(el) {
    return !el.querySelector("*") && el.textContent == "";
}

function hasBlockDescendant(el) {
    return !!el.querySelector(BLOCKISH_SELECTOR);
}

// A <pre> the schema can represent: only text, optionally inside one plain
// <code>. Anything else (links, bold, <br>) would lose its markup in a
// text-only code block.
function isSimplePre(el) {
    return Array.from(el.childNodes).every((child) => {
        if (child.nodeType == 3) return true;
        return (
            child.nodeType == 1 &&
            child.localName == "code" &&
            child.attributes.length == 0 &&
            Array.from(child.childNodes).every((c) => c.nodeType == 3)
        );
    });
}

// Decide what a generic block element (<div>, <center>, ...) becomes from the
// kinds of children it has: only blocks -> a container; only inline content
// -> a textblock; a mix can't be represented without inventing paragraphs, so
// it is kept verbatim.
function classifyBlock(el) {
    let blocks = 0;
    let inlines = 0;
    Array.from(el.childNodes).forEach((child) => {
        if (child.nodeType == 3) {
            if (child.nodeValue.trim() != "") inlines++;
        } else if (child.nodeType == 1) {
            if (isBlockish(child)) blocks++;
            else inlines++;
        }
    });
    if (blocks && inlines) return "raw";
    return blocks ? "container" : "textblock";
}

// Is this element one of the marks the schema models directly (and so ranks
// ahead of or behind the generic marks)?
function isModeledMark(el) {
    if (el.localName == "a") return el.hasAttribute("href");
    if (el.localName == "dw-style") return true;
    return MODELED_MARK_TAGS.has(el.localName) && el.attributes.length == 0;
}

function hasModeledAncestor(el) {
    for (let node = el.parentNode; node && node.nodeType == 1; node = node.parentNode) {
        if (isModeledMark(node)) return true;
        if (!INLINE_PARENTS.has(node.localName)) return false;
    }
    return false;
}

// ProseMirror keeps one of any two equal marks, so a generic element nested
// inside an identical one (the same tag and attributes, e.g. two
// <span style="font-size: 2em"> one inside the other) would be merged into it
// and lose its own effect. Report whether an ancestor placeholder is equal to
// the one this element would become.
// Attribute order doesn't matter (class then style is the same mark as style
// then class), so compare as sorted lists.
function canonicalAttrs(attrs) {
    return JSON.stringify(Object.keys(attrs).sort().map((name) => [name, attrs[name]]));
}

function nestsInEqual(el, inner) {
    const x = canonicalAttrs(allAttrs(el));
    for (let node = el.parentNode; node && node.nodeType == 1; node = node.parentNode) {
        let theirs = {};
        try {
            theirs = JSON.parse(node.getAttribute("data-dw-x") || "{}");
        } catch (e) {
            // treat as no attributes
        }
        if (
            node.localName == "dw-inline" &&
            node.getAttribute("data-dw-tag") == el.localName &&
            canonicalAttrs(theirs) == x &&
            node.hasAttribute("data-dw-inner") == inner
        )
            return true;
    }
    return false;
}

function hasModeledDescendant(el) {
    return Array.from(el.querySelectorAll("*")).some(isModeledMark);
}

function toPlaceholder(el, placeholderTag, inner) {
    const placeholder = document.createElement(placeholderTag);
    placeholder.setAttribute("data-dw-tag", el.localName);
    if (inner) placeholder.setAttribute("data-dw-inner", "1");
    const extra = allAttrs(el);
    if (Object.keys(extra).length) placeholder.setAttribute("data-dw-x", JSON.stringify(extra));
    while (el.firstChild) placeholder.appendChild(el.firstChild);
    el.replaceWith(placeholder);
    walk(placeholder);
}

// A table cell whose content is running text (see visitTable).
function isTightCell(el) {
    return (el.localName == "td" || el.localName == "th") && !el.hasAttribute("data-dw-loose");
}

function replaceRaw(el, forceBlock) {
    const html = restoreUserTags(el.outerHTML);
    const parent = el.parentNode;
    const inline =
        !forceBlock &&
        parent &&
        parent.localName &&
        (INLINE_PARENTS.has(parent.localName) || isTightCell(parent));
    el.replaceWith(inline ? rawInline(html) : rawBlock(html));
}

// A <span style="..."> the text-style mark can stand for: nothing but colour,
// highlight and font size, and sitting where that mark's rank puts it -- inside
// any link, outside every other modeled mark, and not around a link. A span
// that doesn't qualify is kept as a generic span, as before.
function isTextStyleSpan(el) {
    if (el.localName != "span" || el.attributes.length != 1 || !el.hasAttribute("style"))
        return false;
    if (!textStyleFromCSS(el.getAttribute("style"))) return false;
    if (el.querySelector("a[href]")) return false;
    for (let node = el.parentNode; node && node.nodeType == 1; node = node.parentNode) {
        const tag = node.localName;
        if (tag == "a" && node.hasAttribute("href")) continue;
        if (tag == "dw-style" || tag == "dw-inline" || isModeledMark(node)) return false;
        if (!INLINE_PARENTS.has(tag)) break;
    }
    return true;
}

// ---- Tables --------------------------------------------------------------
//
// A table becomes editable table nodes only when they can hold it exactly:
// rows of cells in one implicit or attribute-less <tbody>, a rectangular grid
// once colspan/rowspan are counted, and cells whose content is either all
// running text or all blocks. Anything else (captions, column groups, thead/
// tfoot, a cell mixing text and blocks) is kept as an HTML block.

const SPAN_VALUE = /^[1-9]\d{0,2}$/;

function isBlank(node) {
    return node.nodeType == 3 && node.nodeValue.trim() == "";
}

function onlyChildren(el, tags) {
    return Array.from(el.childNodes).every(
        (child) => isBlank(child) || (child.nodeType == 1 && tags.indexOf(child.localName) >= 0)
    );
}

function spanOf(cell, name) {
    if (!cell.hasAttribute(name)) return 1;
    const value = cell.getAttribute(name).trim();
    return SPAN_VALUE.test(value) ? +value : 0;
}

// Cell text is parsed like any other running text, with its whitespace
// collapsed, which only shows if the table, something in it, or something
// around it asks for whitespace to be kept. (Elements around it have already
// been visited, so their style may be stashed in data-dw-x.)
const KEEPS_WHITESPACE = /white-space\s*:\s*(pre|pre-wrap|pre-line|break-spaces)\b/i;

function styleText(el) {
    if (el.hasAttribute("style")) return el.getAttribute("style");
    try {
        return (JSON.parse(el.getAttribute("data-dw-x") || "{}") || {}).style || "";
    } catch (e) {
        return "";
    }
}

function keepsWhitespace(table) {
    const around = [];
    for (let node = table.parentNode; node && node.nodeType == 1; node = node.parentNode)
        around.push(node);
    return [table, ...table.querySelectorAll("*"), ...around].some((el) =>
        KEEPS_WHITESPACE.test(styleText(el))
    );
}

function tableRows(table) {
    if (!validAttrs(table) || !onlyChildren(table, ["tbody"]) || keepsWhitespace(table))
        return null;
    const bodies = Array.from(table.children);
    if (bodies.length != 1 || bodies[0].attributes.length) return null;
    const body = bodies[0];
    if (!onlyChildren(body, ["tr"])) return null;

    const rows = Array.from(body.children);
    if (!rows.length) return null;
    const grid = [];
    for (let r = 0; r < rows.length; r++) {
        const row = rows[r];
        if (!validAttrs(row) || !onlyChildren(row, ["td", "th"]) || !row.children.length)
            return null;
        grid[r] = grid[r] || [];
        let col = 0;
        for (const cell of Array.from(row.children)) {
            if (!validAttrs(cell) || classifyBlock(cell) == "raw") return null;
            const colspan = spanOf(cell, "colspan");
            const rowspan = spanOf(cell, "rowspan");
            if (!colspan || !rowspan || r + rowspan > rows.length) return null;
            while (grid[r][col]) col++;
            for (let i = 0; i < rowspan; i++) {
                grid[r + i] = grid[r + i] || [];
                for (let j = 0; j < colspan; j++) {
                    if (grid[r + i][col + j]) return null;
                    grid[r + i][col + j] = true;
                }
            }
            col += colspan;
        }
    }
    const width = grid[0].length;
    for (const line of grid) {
        if (line.length != width) return null;
        for (let c = 0; c < width; c++) if (!line[c]) return null;
    }
    return rows;
}

function visitTable(table) {
    const rows = tableRows(table);
    if (!rows) return replaceRaw(table, true);

    stashAttrs(table, []);
    rows.forEach((row) => {
        stashAttrs(row, []);
        Array.from(row.children).forEach((cell) => {
            const loose = classifyBlock(cell) == "container";
            stashAttrs(cell, ["colspan", "rowspan"]);
            if (cell.hasAttribute("colspan")) cell.setAttribute("colspan", spanOf(cell, "colspan"));
            if (cell.hasAttribute("rowspan")) cell.setAttribute("rowspan", spanOf(cell, "rowspan"));
            if (loose) cell.setAttribute("data-dw-loose", "1");
            walk(cell);
        });
    });
}

function visit(el) {
    const tag = el.localName;

    if (tag == "dw-user") return;
    if (tag.indexOf("dw-") == 0) return replaceRaw(el);
    if (tag == "table") return visitTable(el);
    if (RAW_BLOCK_TAGS.has(tag)) return replaceRaw(el, true);
    if (!validAttrs(el)) return replaceRaw(el);

    // Dreamwidth cut tags (and the FCK-era div representation).
    if (tag == "cut" || tag == "lj-cut" || (tag == "div" && el.classList.contains("ljcut"))) {
        if (tag == "cut") liftCut(el);
        walk(el);
        return;
    }

    if (KNOWN_BLOCK_TAGS.has(tag)) {
        if (tag == "pre" && !isSimplePre(el)) return replaceRaw(el, true);
        stashAttrs(el, tag == "ol" ? ["start"] : []);
        walk(el);
        return;
    }

    if (tag == "br") {
        stashAttrs(el, []);
        return;
    }

    if (tag == "img") {
        if (!el.hasAttribute("src")) return replaceRaw(el);
        stashAttrs(el, ["src", "alt", "title", "width", "height"]);
        return;
    }

    if (tag == "a" && el.hasAttribute("href")) {
        if (hasBlockDescendant(el)) return replaceRaw(el);
        stashAttrs(el, ["href", "title"]);
        walk(el);
        return;
    }

    if (MODELED_MARK_TAGS.has(tag) && el.attributes.length == 0) {
        if (hasBlockDescendant(el)) return replaceRaw(el);
        walk(el);
        return;
    }

    // Unlinked anchors, <span>, <font>, and modeled marks that carry
    // attributes. Empty ones (<a name="top"></a>) have no text to hang a mark
    // on, so they're kept verbatim.
    if (GENERIC_INLINE_TAGS.indexOf(tag) >= 0) {
        if (isEmpty(el) || hasBlockDescendant(el)) return replaceRaw(el);

        // Marks are an unordered set ranked by type, so a generic element
        // keeps its place only if it sat wholly outside or wholly inside the
        // modeled marks. Wedged between two, it's kept as an opaque fragment.
        const inside = hasModeledAncestor(el);
        if (inside && hasModeledDescendant(el)) return replaceRaw(el);
        if (isTextStyleSpan(el)) {
            const placeholder = document.createElement("dw-style");
            placeholder.setAttribute("data-style", el.getAttribute("style"));
            while (el.firstChild) placeholder.appendChild(el.firstChild);
            el.replaceWith(placeholder);
            walk(placeholder);
            return;
        }
        if (nestsInEqual(el, inside)) return replaceRaw(el);
        toPlaceholder(el, "dw-inline", inside);
        return;
    }

    if (GENERIC_BLOCK.has(tag)) {
        const kind = classifyBlock(el);
        if (kind == "raw") return replaceRaw(el, true);
        toPlaceholder(el, kind == "container" ? "dw-block" : "dw-textblock");
        return;
    }

    // Something we have no model for at all.
    replaceRaw(el);
}

function walk(parent) {
    Array.from(parent.childNodes).forEach((child) => {
        if (child.nodeType == 1) visit(child);
    });
}

// ---- Casual HTML / Markdown -> rich conversion --------------------------
//
// Casual HTML turns newlines into <br /> and links bare URLs on the server,
// and casual HTML/Markdown turn @name into a user tag. The rte1 format does
// none of that, so converting a casual entry to rich text has to do it
// explicitly or the entry would change when it's next displayed.

const URL_RE = /(https?:\/\/[^\s'"<>]+[a-zA-Z0-9_/&=-])/g;
const MENTION_RE = /(^|[^\w/])@([\w-]+)(?:\.([\w.-]*[\w-]))?(?=$|\W)/gm;

function userPlaceholder(name, site) {
    const el = document.createElement("dw-user");
    el.setAttribute("name", name);
    if (site) el.setAttribute("site", site);
    return el;
}

function mentionsIn(text, sites, out) {
    let last = 0;
    let m;
    MENTION_RE.lastIndex = 0;
    while ((m = MENTION_RE.exec(text))) {
        const site = m[3] ? m[3].toLowerCase() : "";
        // An unknown site means the server leaves it as literal text.
        if (site && !(sites && sites.indexOf(site) >= 0)) continue;
        const start = m.index + m[1].length;
        if (start > last) out.push(document.createTextNode(text.slice(last, start)));
        out.push(userPlaceholder(m[2], site));
        last = m.index + m[0].length;
    }
    if (last < text.length) out.push(document.createTextNode(text.slice(last)));
}

function casualPieces(text, opts, inLink, inCode) {
    // URLs first (the server links before it converts mentions).
    const pieces = [];
    if (opts.links && !inLink) {
        let last = 0;
        let m;
        URL_RE.lastIndex = 0;
        while ((m = URL_RE.exec(text))) {
            if (m.index > last) pieces.push({ text: text.slice(last, m.index) });
            pieces.push({ url: m[1] });
            last = m.index + m[1].length;
        }
        if (last < text.length) pieces.push({ text: text.slice(last) });
    } else {
        pieces.push({ text: text });
    }

    const out = [];
    pieces.forEach((piece) => {
        if (piece.url) {
            const a = document.createElement("a");
            a.setAttribute("href", piece.url);
            a.textContent = piece.url;
            out.push(a);
        } else if (opts.mentions && !inLink && !inCode) {
            mentionsIn(piece.text, opts.sites, out);
        } else {
            out.push(document.createTextNode(piece.text));
        }
    });
    return out;
}

function casualText(textNode, opts, inLink, inCode) {
    const text = textNode.nodeValue;
    if (!/\n/.test(text) && !(opts.links && text.indexOf("http") >= 0) && text.indexOf("@") < 0)
        return;

    // A whitespace-only run between blocks is just source formatting.
    if (text.trim() == "") {
        const prev = textNode.previousSibling;
        const next = textNode.nextSibling;
        if (!prev || !next || isBlockish(prev) || isBlockish(next)) return;
    }

    const frag = document.createDocumentFragment();
    text.split(/\r?\n/).forEach((line, i) => {
        if (i > 0) frag.appendChild(document.createElement("br"));
        if (line)
            casualPieces(line, opts, inLink, inCode).forEach((node) => frag.appendChild(node));
    });
    textNode.replaceWith(frag);
}

const TABLE_PARTS = new Set(["table", "tbody", "tr"]);

function casualWalk(parent, opts, inLink, inCode) {
    Array.from(parent.childNodes).forEach((child) => {
        if (child.nodeType == 3) {
            // Whitespace between a table's rows and cells isn't text.
            if (!TABLE_PARTS.has(parent.localName)) casualText(child, opts, inLink, inCode);
        } else if (child.nodeType == 1) {
            const tag = child.localName;
            // Raw chunks and preformatted text keep their newlines.
            if (tag == "pre" || tag == "dw-html-block" || tag == "dw-raw-inline") return;
            casualWalk(child, opts, inLink || tag == "a", inCode || tag == "code");
        }
    });
}

// opts.casual: { links, mentions, sites } -- see above.
export function importHTML(schema, html, opts) {
    opts = opts || {};
    let source = String(html == null ? "" : html);
    if (opts.casual) source = source.replace(/\s+$/, "");

    const tpl = document.createElement("template");
    tpl.innerHTML = markCutTags(balanceUserTags(balancePollTags(source)));
    pairCutMarkers(tpl.content);
    walk(tpl.content);
    if (opts.casual) casualWalk(tpl.content, opts.casual, false, false);
    return PMDOMParser.fromSchema(schema).parse(tpl.content);
}

// Unwrap a list item's leading attribute-less <p> so it renders "tight". Only
// done when the paragraph is the item's text and anything after it is a nested
// list, so multi-paragraph items aren't merged.
function unwrapTightListItems(root) {
    root.querySelectorAll("li").forEach((li) => {
        const first = li.firstElementChild;
        if (!first || first.tagName != "P" || first.attributes.length) return;
        const rest = Array.from(li.children).slice(1);
        if (!rest.every((el) => el.tagName == "UL" || el.tagName == "OL")) return;
        while (first.firstChild) li.insertBefore(first.firstChild, first);
        li.removeChild(first);
    });
}

// The reverse of the cell handling in visitTable: a cell that was running
// text was given a paragraph to edit in; take it back out.
function unwrapTightCells(root) {
    root.querySelectorAll("td, th").forEach((cell) => {
        if (cell.hasAttribute("data-dw-loose")) {
            cell.removeAttribute("data-dw-loose");
            return;
        }
        const first = cell.firstElementChild;
        if (
            cell.childNodes.length != 1 ||
            !first ||
            first.tagName != "P" ||
            first.attributes.length
        )
            return;
        while (first.firstChild) cell.insertBefore(first.firstChild, first);
        cell.removeChild(first);
    });
}

function buildSerializer(schema, rawChunks) {
    const nodes = DOMSerializer.nodesFromSchema(schema);
    const placeholder = (html) => {
        const el = document.createElement("dw-raw-placeholder");
        el.setAttribute("data-key", String(rawChunks.push(html) - 1));
        return el;
    };
    nodes.html_block = (node) => placeholder(node.textContent);
    nodes.html_inline = (node) => placeholder(node.attrs.html);
    return new DOMSerializer(nodes, DOMSerializer.marksFromSchema(schema));
}

// Collapse the newlines the casual-HTML cleaner would turn into <br />, except
// where it leaves them alone (<pre>, <textarea>, scripts, styles).
export function flattenNewlines(html) {
    return html
        .split(/(<(pre|textarea|script|style)\b[\s\S]*?<\/\2\s*>)/i)
        .map((part, i) => (i % 3 == 0 ? part.replace(/\s*\r?\n\s*/g, " ") : i % 3 == 1 ? part : ""))
        .join("");
}

// The reverse of the cut splitting in importHTML. A lead-joined cut's first
// paragraph goes back into the paragraph before it, and a tail-joined cut's
// last paragraph takes back the paragraph after it:
//
//     <p>start</p> <cut><p>hidden</p></cut> <p>rest</p>
//         -> <p>start<cut>hidden</cut>rest</p>
//     <p>start</p> <cut><p>hidden 1</p><p>hidden 2</p></cut>
//         -> <p>start<cut>hidden 1</p><p>hidden 2</p></cut>
//
// The result isn't a tree, so the DOM can't build it: the joins are marked
// with numbered control characters and made on the serialized text. Returns
// the function that does that.
function markCutJoins(root) {
    const mark = (kind, n) => "\u0002" + kind + n + "\u0002";
    const plainP = (el) => isParagraph(el) && !el.attributes.length;
    const joins = [];
    root.querySelectorAll("cut").forEach((cut, n) => {
        const lead = cut.hasAttribute("data-dw-lead");
        const tail = cut.hasAttribute("data-dw-tail");
        const leadSpace = cut.getAttribute("data-dw-lead") == "space";
        const tailSpace = cut.getAttribute("data-dw-tail") == "space";
        cut.removeAttribute("data-dw-lead");
        cut.removeAttribute("data-dw-tail");
        const before = cut.previousElementSibling;
        const after = cut.nextElementSibling;
        const first = cut.firstElementChild;
        const last = cut.lastElementChild;
        const joinLead = lead && isParagraph(before);
        const joinTail = tail && plainP(after) && isParagraph(last);
        if (!joinLead && !joinTail) return;

        cut.prepend(document.createTextNode(mark("C", n)));
        if (joinLead) {
            before.append(document.createTextNode((leadSpace ? " " : "") + mark("L", n)));
            if (plainP(first)) first.prepend(document.createTextNode(mark("F", n)));
        } else if (first == last && plainP(first)) {
            // Only the tail joins: <p><cut>hidden</cut>rest</p>.
            first.prepend(document.createTextNode(mark("S", n)));
        }
        if (joinTail) {
            last.append(document.createTextNode(mark("E", n)));
            after.prepend(document.createTextNode(mark("T", n) + (tailSpace ? " " : "")));
        } else if (joinLead && first == last && plainP(first)) {
            // Only the lead joins, and the cut is that one paragraph's end:
            // <p>start<cut>hidden</cut></p>.
            first.append(document.createTextNode(mark("Z", n)));
        }
        joins.push(n);
    });
    return (html) => {
        joins.forEach((n) => {
            const m = (kind) => mark(kind, n);
            const cutOpen = "(<cut\\b[\\s\\S]*?)" + m("C");
            html = html
                .replace(new RegExp(m("L") + "</p>\\s*" + cutOpen + "<p>" + m("F")), "$1")
                .replace(new RegExp(m("L") + "</p>\\s*" + cutOpen), "$1</p>")
                .replace(new RegExp(cutOpen + "<p>" + m("S")), "<p>$1")
                .replace(new RegExp(m("E") + "</p>(</cut>)\\s*<p>" + m("T")), "$1")
                .replace(new RegExp(m("Z") + "</p></cut>"), "</cut></p>");
        });
        return html.replace(/\u0002[A-Z]\d+\u0002/g, "");
    };
}

// For casual HTML, write plain paragraphs the way casual HTML is written:
// text with a blank line between paragraphs and a newline for each line
// break, which the casual cleaner turns back into <br />s. Everything else
// stays markup, on one line, since a newline beside it would become a
// stray <br />. The newlines are \u0003 until flattenNewlines has run.
function casualParagraphs(root) {
    const plain = (el) =>
        isParagraph(el) && !el.attributes.length && el.textContent.indexOf("\u0002") < 0;
    let lastWasText = false;
    Array.from(root.childNodes).forEach((node) => {
        if (!plain(node)) {
            lastWasText = false;
            return;
        }
        if (!hasContent(node)) {
            node.remove();
            return;
        }
        node.querySelectorAll("br").forEach((br) => {
            if (!br.closest("pre")) br.replaceWith(document.createTextNode("\u0003"));
        });
        if (lastWasText) node.before(document.createTextNode("\u0003\u0003"));
        node.replaceWith(...node.childNodes);
        lastWasText = true;
    });
}

// opts.flatten: produce source for casual HTML: plain paragraphs as lines of
// text, and no other newlines for the server to turn into line breaks.
export function exportHTML(schema, doc, opts) {
    opts = opts || {};

    // Collect the top-level blocks, dropping a trailing empty paragraph: the
    // editor keeps one after block containers (cuts, lists, ...) so you can
    // always type past them, but it's an editing affordance, not content.
    const children = [];
    doc.content.forEach((child) => children.push(child));
    while (
        children.length > 1 &&
        children[children.length - 1].type.name == "paragraph" &&
        !children[children.length - 1].attrs.extra &&
        children[children.length - 1].content.size == 0
    )
        children.pop();

    // An empty document is a single empty paragraph; submit it as nothing.
    if (
        children.length == 1 &&
        children[0].type.name == "paragraph" &&
        !children[0].attrs.extra &&
        children[0].content.size == 0
    )
        return "";

    const rawChunks = [];
    const serializer = buildSerializer(schema, rawChunks);

    // Serialize each top-level block on its own line, for readable source if
    // the entry is later opened in raw HTML mode. rte1 never adds automatic
    // linebreaks, so the whitespace is cosmetic.
    const div = document.createElement("div");
    const wasRaw = render.raw;
    render.raw = true;
    try {
        children.forEach((child, i) => {
            if (i && !opts.flatten) div.appendChild(document.createTextNode("\n\n"));
            div.appendChild(serializer.serializeNode(child, { document }));
        });
    } finally {
        render.raw = wasRaw;
    }

    // List items serialize as <li><p>text</p></li>, but a block <p> inside
    // an <li> makes the browser drop the marker onto its own line with the
    // text below it. For the common single-paragraph item, unwrap the <p>
    // so it renders "tight" (<li>text</li>) -- matching what the editor
    // shows. Multi-block items keep their <p>s (they're genuinely loose).
    unwrapTightListItems(div);
    unwrapTightCells(div);
    const joinCuts = markCutJoins(div);
    if (opts.flatten) casualParagraphs(div);

    // Swap raw-HTML placeholders for markers that survive innerHTML
    // escaping, then substitute the literal chunks back in. </user> is
    // conventionally omitted, but only in markup we generated -- never
    // inside a raw chunk, which is emitted exactly as stored.
    div.querySelectorAll("dw-raw-placeholder").forEach((ph) => {
        ph.replaceWith(
            document.createTextNode("\u0001DWRAW" + ph.getAttribute("data-key") + "\u0001")
        );
    });
    const html = joinCuts(div.innerHTML.replace(/<\/user>/g, "")).replace(
        /\u0001DWRAW(\d+)\u0001/g,
        (m, key) => rawChunks[+key]
    );
    return opts.flatten ? flattenNewlines(html).replace(/\u0003/g, "\n") : html;
}

// If pasted plain text is Dreamwidth block markup (a poll, an embed), return
// it so it can become an HTML block rather than literal, escaped text.
export function rawBlockFromText(text) {
    const trimmed = String(text || "").trim();
    const m = /^<(poll|lj-poll|site-embed|lj-embed|iframe|object|embed)\b/i.exec(trimmed);
    if (!m) return null;
    // <embed> has no closing tag.
    if (m[1].toLowerCase() == "embed") return /^<embed\b[^<]*>$/i.test(trimmed) ? trimmed : null;
    const closer = new RegExp("</" + m[1] + "\\s*>$|/>$", "i");
    return closer.test(trimmed) ? trimmed : null;
}
