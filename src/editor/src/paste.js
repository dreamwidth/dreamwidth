// src/editor/src/paste.js
//
// Pasting Dreamwidth block markup. A poll's code, copied from the poll
// creation page, or an embed's code is plain text that looks like HTML; pasted
// as text it would become escaped, literal characters. Recognize it and drop it
// in as an HTML block instead, which is how polls and embeds are carried.
//
// Authors:
//     Mark Smith <mark@qq.is>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself.  For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

import { Plugin } from "prosemirror-state";
import { rawBlockFromText } from "./serialize.js";

// Insert a literal-HTML block after the block holding the cursor (replacing it
// if it is an empty paragraph), staying inside whatever holds that block -- a
// poll or embed added inside a cut tag, list or table cell stays there.
export function rawBlockTransaction(state, html) {
    const type = state.schema.nodes.html_block;
    const node = type.create(null, html ? state.schema.text(html) : null);
    const $from = state.selection.$from;
    for (let d = $from.depth; d > 0; d--) {
        const block = $from.node(d);
        const parent = $from.node(d - 1);
        const index = $from.index(d - 1);
        if (block.type.name == "paragraph" && block.content.size == 0) {
            if (parent.canReplaceWith(index, index + 1, type))
                return state.tr.replaceWith($from.before(d), $from.after(d), node);
        } else if (parent.canReplaceWith(index + 1, index + 1, type)) {
            return state.tr.insert($from.after(d), node);
        }
    }
    return state.tr.insert($from.depth ? $from.after(1) : $from.pos, node);
}

export function insertRawBlock(view, html) {
    view.dispatch(rawBlockTransaction(view.state, html).scrollIntoView());
    view.focus();
}

export function pastePlugin() {
    return new Plugin({
        props: {
            handlePaste(view, event) {
                if (!event.clipboardData) return false;
                // Inside a code or HTML block, text is just text.
                if (view.state.selection.$from.parent.type.spec.code) return false;
                const raw = rawBlockFromText(event.clipboardData.getData("text/plain"));
                if (!raw) return false;
                insertRawBlock(view, raw);
                return true;
            },
        },
    });
}
