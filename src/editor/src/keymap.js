// src/editor/src/keymap.js
//
// Keyboard shortcuts. Mod = Cmd on Mac, Ctrl elsewhere.
//
// Authors:
//     Mark Smith <mark@qq.is>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself.  For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

import { keymap } from "prosemirror-keymap";
import { baseKeymap, toggleMark, chainCommands, exitCode } from "prosemirror-commands";
import { undo, redo } from "prosemirror-history";
import { undoInputRule } from "prosemirror-inputrules";
import { splitListItem, liftListItem, sinkListItem } from "prosemirror-schema-list";
import { goToNextCell, isInTable } from "prosemirror-tables";
import { indent, outdent, inList, unjoinCut } from "./commands.js";

function tabCommand(schema, direction, listCommand) {
    return (state, dispatch) => {
        if (inList(state, schema)) return listCommand(state, dispatch);
        if (isInTable(state)) return goToNextCell(direction)(state, dispatch);
        return false;
    };
}

export function buildKeymap(schema, commands) {
    const keys = {
        "Mod-z": undo,
        "Shift-Mod-z": redo,
        "Mod-y": redo,
        Backspace: chainCommands(undoInputRule, unjoinCut(schema)),

        "Mod-b": toggleMark(schema.marks.strong),
        "Mod-i": toggleMark(schema.marks.em),
        "Mod-u": toggleMark(schema.marks.underline),
        "Mod-`": toggleMark(schema.marks.code),
        "Mod-k": commands.editLink,

        Enter: splitListItem(schema.nodes.list_item),
        "Mod-[": outdent(schema),
        "Mod-]": indent(schema),
        // Tab nests a list item and otherwise moves between table cells --
        // whichever the cursor is nearer to, so moving off the last cell of a
        // table never falls through to the list around it.
        Tab: tabCommand(schema, 1, sinkListItem(schema.nodes.list_item)),
        "Shift-Tab": tabCommand(schema, -1, liftListItem(schema.nodes.list_item)),

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
