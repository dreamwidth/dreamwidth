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

import { textDialog } from "./dialogs.js";

// <cut>: a bordered region with a non-editable header showing the cut's link
// text, plus a button to change it.
export class CutView {
    constructor(node, view, getPos, strings) {
        this.strings = strings;

        this.dom = document.createElement("div");
        this.dom.className = "dw-editor-cut";

        this.header = document.createElement("div");
        this.header.className = "dw-editor-cut-header";
        this.header.contentEditable = "false";

        this.label = document.createElement("span");
        this.label.className = "dw-editor-cut-label";

        const edit = document.createElement("button");
        edit.type = "button";
        edit.className = "dw-editor-cut-edit";
        edit.textContent = strings.cutEdit;
        edit.addEventListener("click", (e) => {
            e.preventDefault();
            const current = view.state.doc.nodeAt(getPos());
            textDialog(strings.cutCaption, strings, current.attrs.text).then((text) => {
                if (text == null) return;
                view.dispatch(
                    view.state.tr.setNodeMarkup(getPos(), null, { text: text })
                );
                view.focus();
            });
        });

        this.header.appendChild(this.label);
        this.header.appendChild(edit);
        this.dom.appendChild(this.header);

        this.contentDOM = document.createElement("div");
        this.contentDOM.className = "dw-editor-cut-content";
        this.dom.appendChild(this.contentDOM);

        this.setLabel(node);
    }

    setLabel(node) {
        this.label.textContent = node.attrs.text || this.strings.cutDefault;
    }

    update(node) {
        if (node.type.name != "cut") return false;
        this.setLabel(node);
        return true;
    }

    stopEvent(event) {
        // Header interactions (the edit button) are ours, not ProseMirror's.
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

// html_block: source-editable literal HTML, visually labeled so it's clear
// this chunk is passed through as-is.
export class HtmlBlockView {
    constructor(node, view, getPos, strings) {
        this.dom = document.createElement("div");
        this.dom.className = "dw-editor-html-block";

        this.badge = document.createElement("div");
        this.badge.className = "dw-editor-html-badge";
        this.badge.contentEditable = "false";
        this.badge.textContent = strings.htmlBlockLabel;
        this.dom.appendChild(this.badge);

        this.contentDOM = document.createElement("pre");
        this.contentDOM.className = "dw-editor-html-source";
        this.dom.appendChild(this.contentDOM);
    }

    update(node) {
        return node.type.name == "html_block";
    }

    ignoreMutation(mutation) {
        return !this.contentDOM.contains(mutation.target);
    }
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
