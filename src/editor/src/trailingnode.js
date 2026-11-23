// Keep an empty paragraph at the very end of the document, so there's always
// somewhere to put the cursor after a block that can't be "typed past" -- a
// cut, a list, a blockquote, a code or HTML block. Without this, inserting one
// of those as the last thing in the entry traps the cursor inside it.
//
// The trailing paragraph is purely an editing affordance; exportHTML drops a
// trailing empty paragraph so it never reaches the saved entry.

import { Plugin, PluginKey } from "prosemirror-state";

// Returns a transaction that appends an empty paragraph if the document
// doesn't already end with one, or null if nothing is needed.
export function appendTrailingParagraph(state) {
    const last = state.doc.lastChild;
    if (last && last.type.name == "paragraph") return null;
    const para = state.schema.nodes.paragraph.create();
    return state.tr.insert(state.doc.content.size, para);
}

export function trailingNode() {
    return new Plugin({
        key: new PluginKey("trailingNode"),
        appendTransaction(transactions, oldState, newState) {
            if (!transactions.some((tr) => tr.docChanged)) return null;
            const tr = appendTrailingParagraph(newState);
            if (tr) tr.setMeta("addToHistory", false);
            return tr;
        },
    });
}
