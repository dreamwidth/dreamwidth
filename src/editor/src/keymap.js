// Keyboard shortcuts. Mod = Cmd on Mac, Ctrl elsewhere.

import { keymap } from "prosemirror-keymap";
import { baseKeymap, toggleMark, chainCommands, exitCode } from "prosemirror-commands";
import { undo, redo } from "prosemirror-history";
import { undoInputRule } from "prosemirror-inputrules";
import { splitListItem, liftListItem, sinkListItem } from "prosemirror-schema-list";

export function buildKeymap(schema, commands) {
    const keys = {
        "Mod-z": undo,
        "Shift-Mod-z": redo,
        "Mod-y": redo,
        Backspace: undoInputRule,

        "Mod-b": toggleMark(schema.marks.strong),
        "Mod-i": toggleMark(schema.marks.em),
        "Mod-u": toggleMark(schema.marks.underline),
        "Mod-`": toggleMark(schema.marks.code),
        "Mod-k": commands.editLink,

        Enter: splitListItem(schema.nodes.list_item),
        "Mod-[": liftListItem(schema.nodes.list_item),
        "Mod-]": sinkListItem(schema.nodes.list_item),
        Tab: sinkListItem(schema.nodes.list_item),
        "Shift-Tab": liftListItem(schema.nodes.list_item),

        // Leave a code/html block downward
        "Mod-Enter": exitCode,
        "Shift-Enter": chainCommands(exitCode, (state, dispatch) => {
            if (dispatch)
                dispatch(
                    state.tr
                        .replaceSelectionWith(schema.nodes.hard_break.create())
                        .scrollIntoView()
                );
            return true;
        }),
    };

    return [keymap(keys), keymap(baseKeymap)];
}
