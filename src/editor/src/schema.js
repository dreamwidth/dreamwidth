// Document schema for the Dreamwidth rich text editor.
//
// The document serializes to plain HTML plus Dreamwidth's special tags, so
// every node/mark here corresponds directly to markup the server-side cleaner
// (LJ::CleanHTML) understands under the rte1 format. DW-specific pieces:
//
//   cut         — <cut text="...">...</cut>, nestable
//   user        — <user name="..." site="...">, an inline atom
//   html_block  — a literal-HTML escape hatch; its text content is emitted
//                 verbatim (for embeds, polls, tables the table nodes can't
//                 hold exactly, and anything else the schema doesn't model)
//
// Tables come from prosemirror-tables, and text_style carries the toolbar's
// text color, highlight and size as <span style="...">. Alignment and indent
// are text-align and margin-left in a block's preserved style (commands.js).
//
// Existing entries contain plenty of markup the editor has no toolbar button
// for (<span style>, <font>, <center>, <a name>, class="...", ...). Opening
// one must not silently drop any of it, so the schema carries it through:
//
//   extra          — a node/mark attribute holding every HTML attribute the
//                    schema doesn't model itself (class, style, id, align...)
//   html_textblock — <div>, <center>, ... holding inline content
//   html_container — <div>, <center>, ... holding blocks
//   html_mark      — <span>, <font>, <small>, <a name>, ... around inline text
//   html_inline    — an empty inline element (<a name="x"></a>) kept verbatim
//
// These generic pieces and the `extra` attributes are only ever produced by
// serialize.js's import pre-pass, which stashes the original tag and
// attributes on placeholder elements (data-dw-tag / data-dw-x). The parseDOM
// rules below read those placeholders and nothing else, so pasting arbitrary
// web content still gets the clean, schema-only treatment.

import { Schema } from "prosemirror-model";
import { tableNodes } from "prosemirror-tables";
import { parseStyle, formatStyle, TEXT_STYLE_PROPS } from "./style.js";

// Serialization mode. exportHTML sets raw = true while producing the stored
// markup; for the live editor view event-handler attributes (onclick=...) are
// left off so opening somebody else's entry can't run script in the editor.
export const render = { raw: false };

// HTML tags the html_* pieces may use. Import only ever stores tags from these
// lists, and toDOM re-checks, so a corrupted attribute can't mint arbitrary
// elements.
export const GENERIC_BLOCK_TAGS = [
    "div",
    "center",
    "section",
    "article",
    "aside",
    "header",
    "footer",
    "nav",
    "main",
    "figure",
    "figcaption",
    "address",
];

export const GENERIC_INLINE_TAGS = [
    "span",
    "font",
    "small",
    "big",
    "tt",
    "kbd",
    "samp",
    "cite",
    "abbr",
    "acronym",
    "q",
    "mark",
    "ins",
    "del",
    "dfn",
    "var",
    "bdo",
    "bdi",
    "time",
    "data",
    "nobr",
    // Unlinked anchors (<a name>) and styled variants of the modeled marks.
    "a",
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
];

const BLOCK_SET = new Set(GENERIC_BLOCK_TAGS);
const INLINE_SET = new Set(GENERIC_INLINE_TAGS);

const EVENT_ATTR = /^on/i;

// The server's cleaner drops any attribute whose value (ignoring whitespace)
// contains one of these schemes (LJ::CleanHTML::clean). The live editor view
// never goes through the cleaner, so it applies the same rule before putting
// an imported attribute on a real element -- an old entry's href="javascript:..."
// must not become a live link in the editor. The stored markup is untouched.
const UNSAFE_VALUE = /(?:jscript|livescript|javascript|vbscript|^about|data):/i;

export function safeForView(value) {
    return !UNSAFE_VALUE.test(String(value).replace(/[\s\x0b\x00]+/g, ""));
}

// Set an attribute for the live view only if it's safe; for export, always.
function viewAttr(attrs, name, value) {
    if (render.raw || safeForView(value)) attrs[name] = value;
    return attrs;
}

// Add a node's preserved attributes to a toDOM attribute object.
function withExtra(attrs, extra) {
    if (extra) {
        Object.keys(extra).forEach((name) => {
            if (!render.raw && (EVENT_ATTR.test(name) || !safeForView(extra[name]))) return;
            if (!(name in attrs)) attrs[name] = extra[name];
        });
    }
    return attrs;
}

// Read the attributes serialize.js stashed on an element during import.
function readExtra(dom) {
    const raw = dom.getAttribute("data-dw-x");
    if (!raw) return null;
    try {
        const extra = JSON.parse(raw);
        return extra && typeof extra == "object" && Object.keys(extra).length ? extra : null;
    } catch (e) {
        return null;
    }
}

function extraOf(dom) {
    return { extra: readExtra(dom) };
}

const EXTRA = { extra: { default: null } };

function userAttrs(dom) {
    const name =
        dom.getAttribute("name") || dom.getAttribute("user") || dom.getAttribute("comm");
    if (!name) return false;
    // A name supplied via comm= marks a community; otherwise assume a person.
    // ctype is display-only (it picks the chip's head icon) and is never
    // serialized back out -- the server figures out the real type.
    const ctype = dom.getAttribute("comm") ? "C" : "P";
    return { name: name, site: dom.getAttribute("site") || "", ctype: ctype };
}

function genericAttrs(allowed, fallback) {
    return (dom) => {
        const tag = dom.getAttribute("data-dw-tag");
        return { tag: allowed.has(tag) ? tag : fallback, extra: readExtra(dom) };
    };
}

function genericTag(node, allowed, fallback) {
    return allowed.has(node.attrs.tag) ? node.attrs.tag : fallback;
}

const nodes = {
    doc: { content: "block+" },

    paragraph: {
        attrs: EXTRA,
        content: "inline*",
        group: "block",
        parseDOM: [{ tag: "p", getAttrs: extraOf }],
        toDOM(node) {
            return ["p", withExtra({}, node.attrs.extra), 0];
        },
    },

    blockquote: {
        attrs: EXTRA,
        content: "block+",
        group: "block",
        defining: true,
        parseDOM: [{ tag: "blockquote", getAttrs: extraOf }],
        toDOM(node) {
            return ["blockquote", withExtra({}, node.attrs.extra), 0];
        },
    },

    horizontal_rule: {
        attrs: EXTRA,
        group: "block",
        parseDOM: [{ tag: "hr", getAttrs: extraOf }],
        toDOM(node) {
            return ["hr", withExtra({}, node.attrs.extra)];
        },
    },

    heading: {
        attrs: { level: { default: 2 }, extra: { default: null } },
        content: "inline*",
        group: "block",
        defining: true,
        parseDOM: [1, 2, 3, 4, 5, 6].map((level) => ({
            tag: "h" + level,
            getAttrs: (dom) => ({ level: level, extra: readExtra(dom) }),
        })),
        toDOM(node) {
            return ["h" + node.attrs.level, withExtra({}, node.attrs.extra), 0];
        },
    },

    code_block: {
        attrs: EXTRA,
        content: "text*",
        marks: "",
        group: "block",
        code: true,
        defining: true,
        parseDOM: [{ tag: "pre", preserveWhitespace: "full", getAttrs: extraOf }],
        toDOM(node) {
            return ["pre", withExtra({}, node.attrs.extra), ["code", 0]];
        },
    },

    // Dreamwidth cut tag. Rendered in-editor by CutView (nodeviews.js).
    cut: {
        content: "block+",
        group: "block",
        defining: true,
        attrs: { text: { default: "" } },
        parseDOM: [
            { tag: "cut", getAttrs: (dom) => ({ text: dom.getAttribute("text") || "" }) },
            { tag: "lj-cut", getAttrs: (dom) => ({ text: dom.getAttribute("text") || "" }) },
            // FCKeditor-era representation
            { tag: "div.ljcut", getAttrs: (dom) => ({ text: dom.getAttribute("text") || "" }) },
        ],
        toDOM(node) {
            return node.attrs.text ? ["cut", { text: node.attrs.text }, 0] : ["cut", 0];
        },
    },

    // Dreamwidth user/journal link. serialize.js rewrites the conventionally
    // unclosed <user name="..."> into balanced <dw-user> elements before the
    // browser parses them, which is why dw-user appears here.
    user: {
        inline: true,
        group: "inline",
        atom: true,
        draggable: true,
        attrs: { name: {}, site: { default: "" }, ctype: { default: "P" } },
        parseDOM: [
            { tag: "dw-user", getAttrs: userAttrs },
            { tag: "user", getAttrs: userAttrs },
        ],
        toDOM(node) {
            const attrs = { name: node.attrs.name };
            if (node.attrs.site) attrs.site = node.attrs.site;
            return ["user", attrs];
        },
    },

    // Literal HTML block: edited as source text, emitted verbatim on export.
    // serialize.js captures unsupported block markup (tables, polls, embeds,
    // ...) into <dw-html-block> wrappers before parsing.
    html_block: {
        content: "text*",
        marks: "",
        group: "block",
        code: true,
        defining: true,
        isolating: true,
        parseDOM: [{ tag: "dw-html-block", preserveWhitespace: "full" }],
        toDOM() {
            return ["dw-html-block", 0];
        },
    },

    // <div>, <center>, ... whose content is inline (text, <br>, <span>, ...).
    html_textblock: {
        attrs: { tag: { default: "div" }, extra: { default: null } },
        content: "inline*",
        group: "block",
        parseDOM: [
            { tag: "dw-textblock", getAttrs: genericAttrs(BLOCK_SET, "div") },
        ],
        toDOM(node) {
            return [genericTag(node, BLOCK_SET, "div"), withExtra({}, node.attrs.extra), 0];
        },
    },

    // <div>, <center>, ... whose content is other blocks.
    html_container: {
        attrs: { tag: { default: "div" }, extra: { default: null } },
        content: "block+",
        group: "block",
        defining: true,
        parseDOM: [{ tag: "dw-block", getAttrs: genericAttrs(BLOCK_SET, "div") }],
        toDOM(node) {
            return [genericTag(node, BLOCK_SET, "div"), withExtra({}, node.attrs.extra), 0];
        },
    },

    // An empty inline element kept verbatim, e.g. <a name="top"></a>. Shown as
    // a small chip (nodeviews.js); exported through the raw-chunk placeholder.
    html_inline: {
        inline: true,
        group: "inline",
        atom: true,
        draggable: true,
        attrs: { html: { default: "" } },
        parseDOM: [
            { tag: "dw-raw-inline", getAttrs: (dom) => ({ html: dom.getAttribute("data-html") || "" }) },
        ],
        toDOM(node) {
            return ["dw-raw-inline", { "data-html": node.attrs.html }];
        },
    },

    image: {
        inline: true,
        group: "inline",
        draggable: true,
        attrs: {
            src: {},
            alt: { default: "" },
            title: { default: "" },
            width: { default: null },
            height: { default: null },
            extra: { default: null },
        },
        parseDOM: [
            {
                tag: "img[src]",
                getAttrs(dom) {
                    return {
                        src: dom.getAttribute("src"),
                        alt: dom.getAttribute("alt") || "",
                        title: dom.getAttribute("title") || "",
                        width: dom.getAttribute("width"),
                        height: dom.getAttribute("height"),
                        extra: readExtra(dom),
                    };
                },
            },
        ],
        toDOM(node) {
            const attrs = viewAttr({}, "src", node.attrs.src);
            if (node.attrs.alt) attrs.alt = node.attrs.alt;
            if (node.attrs.title) attrs.title = node.attrs.title;
            if (node.attrs.width) attrs.width = node.attrs.width;
            if (node.attrs.height) attrs.height = node.attrs.height;
            return ["img", withExtra(attrs, node.attrs.extra)];
        },
    },

    hard_break: {
        attrs: EXTRA,
        inline: true,
        group: "inline",
        selectable: false,
        parseDOM: [{ tag: "br", getAttrs: extraOf }],
        toDOM(node) {
            return ["br", withExtra({}, node.attrs.extra)];
        },
    },

    ordered_list: {
        content: "list_item+",
        group: "block",
        attrs: { start: { default: 1 }, extra: { default: null } },
        parseDOM: [
            {
                tag: "ol",
                getAttrs(dom) {
                    return {
                        start: dom.hasAttribute("start") ? +dom.getAttribute("start") : 1,
                        extra: readExtra(dom),
                    };
                },
            },
        ],
        toDOM(node) {
            const attrs = withExtra({}, node.attrs.extra);
            if (node.attrs.start != 1) attrs.start = node.attrs.start;
            return ["ol", attrs, 0];
        },
    },

    bullet_list: {
        attrs: EXTRA,
        content: "list_item+",
        group: "block",
        parseDOM: [{ tag: "ul", getAttrs: extraOf }],
        toDOM(node) {
            return ["ul", withExtra({}, node.attrs.extra), 0];
        },
    },

    // An item may start with something other than a paragraph (a nested list,
    // an HTML block), so don't insist on one.
    list_item: {
        attrs: EXTRA,
        content: "block+",
        defining: true,
        parseDOM: [{ tag: "li", getAttrs: extraOf }],
        toDOM(node) {
            return ["li", withExtra({}, node.attrs.extra), 0];
        },
    },

    text: { group: "inline" },
};

// Tables (prosemirror-tables). serialize.js only lets a table through as these
// nodes when the editor can represent it exactly -- a plain grid of rows and
// cells, no caption or column groups -- and keeps any other table as an HTML
// block. Every table, row and cell attribute (border, width, bgcolor, style,
// ...) rides along in `extra`. `loose` marks a cell whose stored content was
// already blocks (<td><p>..</p></td>); other cells hold one paragraph for
// editing that is unwrapped again on export, so <td>text</td> stays that way.
const tables = tableNodes({
    tableGroup: "block",
    cellContent: "block+",
    cellAttributes: {
        extra: {
            default: null,
            getFromDOM: readExtra,
            setDOMAttr: (value, attrs) => withExtra(attrs, value),
        },
        loose: {
            default: false,
            getFromDOM: (dom) => dom.hasAttribute("data-dw-loose") || null,
            setDOMAttr: (value, attrs) => {
                if (value) attrs["data-dw-loose"] = "1";
            },
        },
    },
});

tables.table.attrs = EXTRA;
tables.table.parseDOM = [{ tag: "table", getAttrs: extraOf }];
tables.table.toDOM = (node) => ["table", withExtra({}, node.attrs.extra), ["tbody", 0]];
tables.table_row.attrs = EXTRA;
tables.table_row.parseDOM = [{ tag: "tr", getAttrs: extraOf }];
tables.table_row.toDOM = (node) => ["tr", withExtra({}, node.attrs.extra), 0];
Object.assign(nodes, tables);

// Text colour, highlight and font size, as <span style="...">. Imported only
// from a span whose style holds nothing but these (serialize.js), so
// everything else about a span stays in html_mark.
function textStyleAttrs(dom) {
    const decls = parseStyle(dom.getAttribute("data-style"));
    if (!decls) return false;
    const attrs = { color: null, background: null, fontSize: null };
    for (const [prop, value] of decls) {
        if (!TEXT_STYLE_PROPS[prop]) return false;
        attrs[TEXT_STYLE_PROPS[prop]] = value;
    }
    return attrs;
}

export function textStyleCSS(attrs) {
    const decls = [];
    Object.keys(TEXT_STYLE_PROPS).forEach((prop) => {
        const value = attrs[TEXT_STYLE_PROPS[prop]];
        if (value) decls.push([prop, value]);
    });
    return formatStyle(decls);
}

const marks = {
    // <span>, <font>, <small>, <a name>, or a modeled tag that carried
    // attributes (<b class="x">). Listed first so it wraps the other marks, which
    // is the right nesting for an element that sat outside them. One that sat
    // inside a modeled mark (<strong><span style=...>) is an html_mark_inner,
    // listed last, so the stored nesting comes back the same -- otherwise a
    // normal-weight span inside <strong> would come out wrapping it, and bold.
    html_mark: {
        attrs: { tag: { default: "span" }, extra: { default: null } },
        excludes: "",
        parseDOM: [
            {
                tag: "dw-inline:not([data-dw-inner])",
                getAttrs: genericAttrs(INLINE_SET, "span"),
            },
        ],
        toDOM(mark) {
            return [genericTag(mark, INLINE_SET, "span"), withExtra({}, mark.attrs.extra), 0];
        },
    },

    link: {
        attrs: { href: {}, title: { default: null }, extra: { default: null } },
        inclusive: false,
        parseDOM: [
            {
                tag: "a[href]",
                getAttrs(dom) {
                    return {
                        href: dom.getAttribute("href"),
                        title: dom.getAttribute("title"),
                        extra: readExtra(dom),
                    };
                },
            },
        ],
        toDOM(mark) {
            const attrs = viewAttr({}, "href", mark.attrs.href);
            if (mark.attrs.title) attrs.title = mark.attrs.title;
            return ["a", withExtra(attrs, mark.attrs.extra), 0];
        },
    },

    // Sits inside links, so a colour applied to linked text shows (a link's
    // own colour would otherwise win), and outside the other marks.
    text_style: {
        attrs: {
            color: { default: null },
            background: { default: null },
            fontSize: { default: null },
        },
        parseDOM: [{ tag: "dw-style", getAttrs: textStyleAttrs }],
        toDOM(mark) {
            const attrs = {};
            const css = textStyleCSS(mark.attrs);
            if (css && (render.raw || safeForView(css))) attrs.style = css;
            return ["span", attrs, 0];
        },
    },

    em: {
        parseDOM: [{ tag: "i" }, { tag: "em" }, { style: "font-style=italic" }],
        toDOM() {
            return ["em", 0];
        },
    },

    strong: {
        parseDOM: [
            { tag: "strong" },
            // Work around Google Docs et al. misusing <b> as a wrapper with
            // font-weight: normal (same trick as prosemirror-schema-basic).
            { tag: "b", getAttrs: (dom) => dom.style.fontWeight != "normal" && null },
            {
                style: "font-weight",
                getAttrs: (value) => /^(bold(er)?|[5-9]\d{2,})$/.test(value) && null,
            },
        ],
        toDOM() {
            return ["strong", 0];
        },
    },

    underline: {
        parseDOM: [{ tag: "u" }, { style: "text-decoration=underline" }],
        toDOM() {
            return ["u", 0];
        },
    },

    strike: {
        parseDOM: [
            { tag: "s" },
            { tag: "strike" },
            { tag: "del" },
            { style: "text-decoration=line-through" },
        ],
        toDOM() {
            return ["s", 0];
        },
    },

    code: {
        parseDOM: [{ tag: "code" }],
        toDOM() {
            return ["code", 0];
        },
    },

    sub: {
        parseDOM: [{ tag: "sub" }],
        toDOM() {
            return ["sub", 0];
        },
    },

    sup: {
        parseDOM: [{ tag: "sup" }],
        toDOM() {
            return ["sup", 0];
        },
    },

    // See html_mark: the same thing, but nested inside the modeled marks.
    html_mark_inner: {
        attrs: { tag: { default: "span" }, extra: { default: null } },
        excludes: "",
        parseDOM: [
            { tag: "dw-inline[data-dw-inner]", getAttrs: genericAttrs(INLINE_SET, "span") },
        ],
        toDOM(mark) {
            return [genericTag(mark, INLINE_SET, "span"), withExtra({}, mark.attrs.extra), 0];
        },
    },
};

export const schema = new Schema({ nodes, marks });
