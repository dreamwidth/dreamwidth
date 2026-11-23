// Pasting Dreamwidth block markup. A poll's code, copied from the poll
// creation page, or an embed's code is plain text that looks like HTML; pasted
// as text it would become escaped, literal characters. Recognize it and drop it
// in as an HTML block instead, which is how polls and embeds are carried.

import { Plugin } from "prosemirror-state";
import { rawBlockFromText } from "./serialize.js";

// Insert a literal-HTML block after the block holding the cursor (replacing it
// if it is an empty paragraph).
export function insertRawBlock(view, html) {
    const state = view.state;
    const type = state.schema.nodes.html_block;
    const node = type.create(null, html ? state.schema.text(html) : null);
    const $from = state.selection.$from;
    let tr = state.tr;
    if ($from.depth == 0) {
        tr = tr.insert($from.pos, node);
    } else {
        const block = $from.node(1);
        if (block.type.name == "paragraph" && block.content.size == 0)
            tr = tr.replaceWith($from.before(1), $from.after(1), node);
        else tr = tr.insert($from.after(1), node);
    }
    view.dispatch(tr.scrollIntoView());
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
