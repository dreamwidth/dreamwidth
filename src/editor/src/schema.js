// Document schema for the Dreamwidth rich text editor.
//
// The document serializes to plain HTML plus Dreamwidth's special tags, so
// every node/mark here corresponds directly to markup the server-side cleaner
// (LJ::CleanHTML) understands under the rte1 format. DW-specific pieces:
//
//   cut        — <cut text="...">...</cut>, nestable
//   user       — <user name="..." site="...">, an inline atom
//   html_block — a literal-HTML escape hatch; its text content is emitted
//                verbatim (for embeds, polls, tables, and anything else the
//                schema doesn't model)

import { Schema } from "prosemirror-model";

function userAttrs(dom) {
    const name =
        dom.getAttribute("name") || dom.getAttribute("user") || dom.getAttribute("comm");
    if (!name) return false;
    return { name: name, site: dom.getAttribute("site") || "" };
}

const nodes = {
    doc: { content: "block+" },

    paragraph: {
        content: "inline*",
        group: "block",
        parseDOM: [{ tag: "p" }],
        toDOM() {
            return ["p", 0];
        },
    },

    blockquote: {
        content: "block+",
        group: "block",
        defining: true,
        parseDOM: [{ tag: "blockquote" }],
        toDOM() {
            return ["blockquote", 0];
        },
    },

    horizontal_rule: {
        group: "block",
        parseDOM: [{ tag: "hr" }],
        toDOM() {
            return ["hr"];
        },
    },

    heading: {
        attrs: { level: { default: 2 } },
        content: "inline*",
        group: "block",
        defining: true,
        parseDOM: [1, 2, 3, 4, 5, 6].map((level) => ({
            tag: "h" + level,
            attrs: { level: level },
        })),
        toDOM(node) {
            return ["h" + node.attrs.level, 0];
        },
    },

    code_block: {
        content: "text*",
        marks: "",
        group: "block",
        code: true,
        defining: true,
        parseDOM: [{ tag: "pre", preserveWhitespace: "full" }],
        toDOM() {
            return ["pre", ["code", 0]];
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
        attrs: { name: {}, site: { default: "" } },
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
            return ["img", attrs];
        },
    },

    hard_break: {
        inline: true,
        group: "inline",
        selectable: false,
        parseDOM: [{ tag: "br" }],
        toDOM() {
            return ["br"];
        },
    },

    ordered_list: {
        content: "list_item+",
        group: "block",
        attrs: { start: { default: 1 } },
        parseDOM: [
            {
                tag: "ol",
                getAttrs(dom) {
                    return { start: dom.hasAttribute("start") ? +dom.getAttribute("start") : 1 };
                },
            },
        ],
        toDOM(node) {
            return node.attrs.start == 1 ? ["ol", 0] : ["ol", { start: node.attrs.start }, 0];
        },
    },

    bullet_list: {
        content: "list_item+",
        group: "block",
        parseDOM: [{ tag: "ul" }],
        toDOM() {
            return ["ul", 0];
        },
    },

    list_item: {
        content: "paragraph block*",
        defining: true,
        parseDOM: [{ tag: "li" }],
        toDOM() {
            return ["li", 0];
        },
    },

    text: { group: "inline" },
};

const marks = {
    link: {
        attrs: { href: {}, title: { default: null } },
        inclusive: false,
        parseDOM: [
            {
                tag: "a[href]",
                getAttrs(dom) {
                    return { href: dom.getAttribute("href"), title: dom.getAttribute("title") };
                },
            },
        ],
        toDOM(mark) {
            const attrs = { href: mark.attrs.href };
            if (mark.attrs.title) attrs.title = mark.attrs.title;
            return ["a", attrs, 0];
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
