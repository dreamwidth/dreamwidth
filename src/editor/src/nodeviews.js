// src/editor/src/nodeviews.js
//
// In-editor rendering for the Dreamwidth-specific nodes. These control only
// what the editor shows while writing; the stored markup comes from the
// schema's toDOM via serialize.js.
//
// Authors:
//     Mark Smith <mark@qq.is>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself.  For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

import { Plugin, PluginKey, Selection, TextSelection } from "prosemirror-state";
import { Decoration, DecorationSet } from "prosemirror-view";

// <cut>: a bordered region whose header holds the cut's link text, editable
// in place.
export class CutView {
    constructor(node, view, getPos, strings) {
        this.dom = document.createElement("div");
        this.dom.className = "dw-editor-cut";

        this.header = document.createElement("div");
        this.header.className = "dw-editor-cut-header";
        this.header.contentEditable = "false";

        const icon = document.createElement("span");
        icon.className = "dw-editor-cut-icon";
        icon.setAttribute("aria-hidden", "true");
        icon.textContent = "\u2702";

        // The link text is an attribute of the cut, not document text, so it
        // gets a field of its own. Each change is a normal transaction, so
        // undo and the draft autosave see it like any other edit.
        this.input = document.createElement("input");
        this.input.type = "text";
        this.input.className = "dw-editor-cut-text";
        this.input.placeholder = strings.cutDefault;
        this.input.setAttribute("aria-label", strings.cutCaption);
        this.input.value = node.attrs.text || "";
        this.input.addEventListener("input", () => {
            const pos = getPos();
            if (pos == null) return;
            view.dispatch(
                view.state.tr.setNodeMarkup(pos, null, { text: this.input.value })
            );
        });
        // Enter or the down arrow moves on into the cut's own text.
        this.input.addEventListener("keydown", (e) => {
            if (e.key != "Enter" && e.key != "ArrowDown") return;
            e.preventDefault();
            const pos = getPos();
            if (pos == null) return;
            const $inside = view.state.doc.resolve(pos + 1);
            view.dispatch(view.state.tr.setSelection(Selection.near($inside)));
            view.focus();
        });

        this.header.appendChild(icon);
        this.header.appendChild(this.input);
        this.dom.appendChild(this.header);

        this.contentDOM = document.createElement("div");
        this.contentDOM.className = "dw-editor-cut-content";
        this.dom.appendChild(this.contentDOM);
        this.setJoins(node);
    }

    // A cut joined to the paragraph above has its link text at the end of
    // that paragraph instead of in its own header (see cutChips).
    setJoins(node) {
        this.dom.classList.toggle("dw-editor-cut-lead", !!node.attrs.lead);
        this.dom.classList.toggle("dw-editor-cut-tail", !!node.attrs.tail);
    }

    update(node) {
        if (node.type.name != "cut") return false;
        this.setJoins(node);
        // Only when it differs, so typing in the field doesn't move its caret.
        const text = node.attrs.text || "";
        if (this.input.value != text) this.input.value = text;
        return true;
    }

    stopEvent(event) {
        // Typing and clicks in the header are the field's, not ProseMirror's.
        return this.header.contains(event.target);
    }

    ignoreMutation(mutation) {
        return !this.contentDOM.contains(mutation.target);
    }
}

// Pick the head icon for a user chip: the external site's badge if the link
// points off-site, otherwise the local person/community/feed identity icon.
function pickIcon(icons, attrs) {
    if (!icons) return null;
    if (attrs.site)
        return (icons.sites && icons.sites[attrs.site.toLowerCase()]) || icons.fallback || null;
    return (icons.local && (icons.local[attrs.ctype] || icons.local.P)) || null;
}

// <user name=...>: an inline chip showing the head icon plus the username,
// mirroring how the rendered userhead looks.
export class UserView {
    constructor(node, icons) {
        this.dom = document.createElement("span");
        this.dom.className =
            "dw-editor-user" + (node.attrs.site ? " dw-editor-user-external" : "");

        const icon = pickIcon(icons, node.attrs);
        if (icon) {
            const img = document.createElement("img");
            img.className = "dw-editor-user-icon";
            img.src = icon.url;
            if (icon.width) img.width = icon.width;
            if (icon.height) img.height = icon.height;
            img.alt = "";
            this.dom.appendChild(img);
        }

        const label = document.createElement("span");
        label.textContent = node.attrs.name;
        this.dom.appendChild(label);

        this.dom.title = node.attrs.site
            ? node.attrs.name + " @ " + node.attrs.site
            : node.attrs.name;
    }
}

// A posted poll's placeholder (<poll-123>), and a poll written out in full.
const POLL_REF = /^<(?:lj-)?poll-(\d+)>$/;
const POLL_MARKUP = /^<(?:lj-)?poll\b[\s\S]*<\/(?:lj-)?poll\s*>$/i;

// What a poll block's preview shows: { id } for a posted poll, or { name,
// questions: [{ text, type, items }] } for poll markup. Null for anything
// else. Parsed in an inert template, and only text is read back out.
export function pollSummary(source) {
    const html = String(source || "").trim();
    const ref = POLL_REF.exec(html);
    if (ref) return { id: ref[1] };
    if (!POLL_MARKUP.test(html)) return null;

    const tpl = document.createElement("template");
    tpl.innerHTML = html;
    const poll = tpl.content.querySelector("poll, lj-poll");
    if (!poll) return null;
    const clean = (text) => text.replace(/\s+/g, " ").trim();
    const questions = Array.from(poll.querySelectorAll("poll-question, lj-pq")).map((q) => {
        let text = "";
        q.childNodes.forEach((child) => {
            const tag = child.nodeType == 1 ? child.localName : null;
            if (tag != "poll-item" && tag != "lj-pi") text += child.textContent;
        });
        return {
            text: clean(text),
            type: (q.getAttribute("type") || "").toLowerCase(),
            items: Array.from(q.querySelectorAll("poll-item, lj-pi")).map((i) =>
                clean(i.textContent)
            ),
        };
    });
    return { name: clean(poll.getAttribute("name") || ""), questions };
}

const ITEM_MARKERS = { radio: "\u25cb", check: "\u2610" };

// html_block: source-editable literal HTML, visually labeled so it's clear
// this chunk is passed through as-is. A poll shows a read-only preview
// instead, and its source only while the cursor is in it (activeHtmlBlock
// marks that), so the button to edit it just moves the cursor there.
export class HtmlBlockView {
    constructor(node, view, getPos, strings) {
        this.strings = strings;
        this.dom = document.createElement("div");
        this.dom.className = "dw-editor-html-block";

        this.badge = document.createElement("div");
        this.badge.className = "dw-editor-html-badge";
        this.badge.contentEditable = "false";
        this.label = document.createElement("span");
        this.badge.appendChild(this.label);
        this.editButton = document.createElement("button");
        this.editButton.type = "button";
        this.editButton.className = "dw-editor-html-edit";
        this.editButton.textContent = strings.pollEditHTML;
        this.editButton.addEventListener("click", (e) => {
            e.preventDefault();
            const pos = getPos();
            if (pos == null) return;
            const end = pos + view.state.doc.nodeAt(pos).nodeSize - 1;
            view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, end)));
            view.focus();
        });
        this.badge.appendChild(this.editButton);
        this.dom.appendChild(this.badge);

        this.preview = document.createElement("div");
        this.preview.className = "dw-editor-poll-preview";
        this.preview.contentEditable = "false";
        this.dom.appendChild(this.preview);

        this.contentDOM = document.createElement("pre");
        this.contentDOM.className = "dw-editor-html-source";
        this.dom.appendChild(this.contentDOM);

        this.render(node);
    }

    render(node) {
        const source = node.textContent;
        if (source === this.source) return;
        this.source = source;
        const poll = pollSummary(source);
        this.dom.classList.toggle("dw-editor-html-poll", !!poll);
        this.label.textContent = poll ? this.strings.pollLabel : this.strings.htmlBlockLabel;
        this.preview.textContent = "";
        if (poll) this.renderPoll(poll);
    }

    renderPoll(poll) {
        const add = (parent, tag, className, text) => {
            const el = document.createElement(tag);
            el.className = className;
            if (text != null) el.textContent = text;
            parent.appendChild(el);
            return el;
        };
        if (poll.id) {
            add(this.preview, "div", "dw-editor-poll-name", this.strings.pollPosted.replace("[[id]]", poll.id));
            const link = add(this.preview, "a", "dw-editor-poll-link", this.strings.pollView);
            link.href = "/poll/?id=" + poll.id;
            link.target = "_blank";
            link.rel = "noopener";
            return;
        }
        if (poll.name) add(this.preview, "div", "dw-editor-poll-name", poll.name);
        poll.questions.forEach((q) => {
            add(this.preview, "div", "dw-editor-poll-question", q.text);
            if (!q.items.length) return;
            const list = add(this.preview, "ul", "dw-editor-poll-items");
            q.items.forEach((item) => {
                const li = add(list, "li", "", item);
                li.setAttribute("data-marker", ITEM_MARKERS[q.type] || "\u2022");
            });
        });
    }

    update(node) {
        if (node.type.name != "html_block") return false;
        this.render(node);
        return true;
    }

    stopEvent(event) {
        return this.badge.contains(event.target) || this.preview.contains(event.target);
    }

    ignoreMutation(mutation) {
        return !this.contentDOM.contains(mutation.target);
    }
}

// Marks the HTML block the cursor is in, so a poll's source shows while it's
// being edited and its preview the rest of the time.
export function activeHtmlBlock() {
    return new Plugin({
        props: {
            decorations(state) {
                const { $head } = state.selection;
                for (let d = $head.depth; d > 0; d--) {
                    if ($head.node(d).type.name != "html_block") continue;
                    const pos = $head.before(d);
                    return DecorationSet.create(state.doc, [
                        Decoration.node(pos, pos + $head.node(d).nodeSize, {
                            class: "dw-editor-html-active",
                        }),
                    ]);
                }
                return null;
            },
        },
    });
}

// html_inline: an empty inline element kept verbatim (<a name="top"></a>),
// shown as a chip with its opening tag.
export class HtmlInlineView {
    constructor(node) {
        this.dom = document.createElement("span");
        this.dom.className = "dw-editor-html-inline";
        this.dom.contentEditable = "false";
        this.render(node);
    }

    render(node) {
        const html = node.attrs.html;
        const open = /^<[^>]*>/.exec(html);
        this.dom.textContent = open ? open[0] : html.slice(0, 40);
        this.dom.title = html;
    }

    update(node) {
        if (node.type.name != "html_inline") return false;
        this.render(node);
        return true;
    }
}

export function buildNodeViews(options) {
    const strings = options.strings;
    const icons = options.icons;
    return {
        cut: (node, view, getPos) => new CutView(node, view, getPos, strings),
        user: (node) => new UserView(node, icons),
        html_block: (node, view, getPos) => new HtmlBlockView(node, view, getPos, strings),
        html_inline: (node) => new HtmlInlineView(node),
    };
}

// A cut that starts partway through a paragraph: its link text goes where the
// reader sees the link, at the end of the visible part of the paragraph, as a
// small editable chip. The paragraphs it's joined to are marked so they can
// be drawn running into the cut and out of it.
function cutChip(view, getPos, strings) {
    const chip = document.createElement("span");
    chip.className = "dw-editor-cut-chip";
    chip.contentEditable = "false";
    const icon = document.createElement("span");
    icon.className = "dw-editor-cut-icon";
    icon.setAttribute("aria-hidden", "true");
    icon.textContent = "\u2702";
    const input = document.createElement("input");
    input.type = "text";
    input.className = "dw-editor-cut-text";
    input.placeholder = strings.cutDefault;
    input.setAttribute("aria-label", strings.cutCaption);
    chip.appendChild(icon);
    chip.appendChild(input);

    // The cut starts right after the end of the paragraph the chip ends.
    const cutPos = () => {
        const pos = getPos();
        if (pos == null) return null;
        const node = view.state.doc.nodeAt(pos + 1);
        return node && node.type.name == "cut" ? pos + 1 : null;
    };
    const fit = () => {
        input.size = Math.max(4, (input.value || input.placeholder).length + 1);
    };
    chip.dwSync = () => {
        const pos = cutPos();
        if (pos == null || document.activeElement == input) return;
        const text = view.state.doc.nodeAt(pos).attrs.text || "";
        if (input.value != text) input.value = text;
        fit();
    };
    input.addEventListener("input", () => {
        fit();
        const pos = cutPos();
        if (pos == null) return;
        const node = view.state.doc.nodeAt(pos);
        view.dispatch(
            view.state.tr.setNodeMarkup(pos, null, Object.assign({}, node.attrs, { text: input.value }))
        );
    });
    // Enter or the down arrow moves on into the cut's own text.
    input.addEventListener("keydown", (e) => {
        if (e.key != "Enter" && e.key != "ArrowDown") return;
        e.preventDefault();
        const pos = cutPos();
        if (pos == null) return;
        view.dispatch(view.state.tr.setSelection(Selection.near(view.state.doc.resolve(pos + 1))));
        view.focus();
    });
    chip.dwSync();
    return chip;
}

export function cutChips(strings) {
    const key = new PluginKey("cutChips");
    return new Plugin({
        key,
        props: {
            decorations(state) {
                const decos = [];
                let n = 0;
                state.doc.descendants((node, pos, parent, index) => {
                    if (node.type.name != "cut") return true;
                    if (node.attrs.lead && index > 0) {
                        const before = parent.child(index - 1);
                        const start = pos - before.nodeSize;
                        decos.push(
                            Decoration.node(start, pos, { class: "dw-editor-cut-lead-para" }),
                            Decoration.widget(pos - 1, (view, getPos) => cutChip(view, getPos, strings), {
                                side: 1,
                                key: "cut-chip-" + n++,
                                ignoreSelection: true,
                                stopEvent: () => true,
                            })
                        );
                    }
                    if (node.attrs.tail && index + 1 < parent.childCount) {
                        const after = parent.child(index + 1);
                        const start = pos + node.nodeSize;
                        decos.push(
                            Decoration.node(start, start + after.nodeSize, {
                                class: "dw-editor-cut-tail-para",
                            })
                        );
                    }
                    return true;
                });
                return decos.length ? DecorationSet.create(state.doc, decos) : null;
            },
        },
        // A chip is kept while its cut is, so bring its text up to date when
        // it changes some other way (undo).
        view: () => ({
            update(view) {
                view.dom.querySelectorAll(".dw-editor-cut-chip").forEach((chip) => {
                    if (chip.dwSync) chip.dwSync();
                });
            },
        }),
    });
}
