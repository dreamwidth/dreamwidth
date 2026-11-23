// Document schema for the Dreamwidth rich text editor.
//
// The document serializes to plain HTML plus Dreamwidth's special tags, so
// every node/mark here corresponds directly to markup the server-side cleaner
// (LJ::CleanHTML) understands under the rte1 format. DW-specific pieces:
//
//   cut         — <cut text="...">...</cut>, nestable
//   user        — <user name="..." site="...">, an inline atom
//   html_block  — a literal-HTML escape hatch; its text content is emitted
//                 verbatim (for embeds, polls, tables, and anything else the
//                 schema doesn't model)
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

// Add a node's preserved attributes to a toDOM attribute object.
function withExtra(attrs, extra) {
    if (extra) {
        Object.keys(extra).forEach((name) => {
            if (!render.raw && EVENT_ATTR.test(name)) return;
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
            const attrs = { src: node.attrs.src };
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

const marks = {
    // <span>, <font>, <small>, <a name>, or a modeled tag that carried
    // attributes (<b class="x">). Listed first so it wraps the other marks.
    html_mark: {
        attrs: { tag: { default: "span" }, extra: { default: null } },
        excludes: "",
        parseDOM: [{ tag: "dw-inline", getAttrs: genericAttrs(INLINE_SET, "span") }],
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
            const attrs = { href: mark.attrs.href };
            if (mark.attrs.title) attrs.title = mark.attrs.title;
            return ["a", withExtra(attrs, mark.attrs.extra), 0];
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
};

export const schema = new Schema({ nodes, marks });
