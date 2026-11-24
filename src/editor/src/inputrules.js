// src/editor/src/inputrules.js
//
// Markdown-style typing shortcuts, so muscle memory from the Markdown format
// keeps working in the rich editor: **bold**, *em*, `code`, # headings,
// > quotes, - lists, ``` code blocks. These only affect what's typed; the
// stored format is still explicit HTML.
//
// Authors:
//     Mark Smith <mark@qq.is>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself.  For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

import {
    inputRules,
    wrappingInputRule,
    textblockTypeInputRule,
    InputRule,
} from "prosemirror-inputrules";

// Apply a mark to the text matched by group 2, deleting the delimiters
// (the classic markInputRule helper).
// Inside inline code the delimiters are literal text (`*ptr*`), so the rule
// stands aside there.
function markInputRule(regexp, markType) {
    return new InputRule(regexp, (state, match, start, end) => {
        const code = markType.schema.marks.code;
        const $start = state.doc.resolve(start);
        if (
            code.isInSet(state.storedMarks || state.selection.$from.marks()) ||
            code.isInSet($start.marks()) ||
            state.doc.rangeHasMark(start, end, code)
        )
            return null;
        const fullStart = start + match[0].indexOf(match[1]);
        const textStart = fullStart + match[1].indexOf(match[2]);
        const textEnd = textStart + match[2].length;

        let tr = state.tr;
        if (textEnd < end) tr.delete(textEnd, end);
        if (textStart > fullStart) tr.delete(fullStart, textStart);
        tr.addMark(fullStart, fullStart + match[2].length, markType.create());
        tr.removeStoredMark(markType);
        return tr;
    });
}

export function buildInputRules(schema) {
    const rules = [
        wrappingInputRule(/^\s*>\s$/, schema.nodes.blockquote),
        wrappingInputRule(
            /^(\d+)\.\s$/,
            schema.nodes.ordered_list,
            (match) => ({ start: +match[1] }),
            (match, node) => node.childCount + node.attrs.start == +match[1]
        ),
        wrappingInputRule(/^\s*([-+*])\s$/, schema.nodes.bullet_list),
        textblockTypeInputRule(/^```$/, schema.nodes.code_block),
        textblockTypeInputRule(/^(#{1,4})\s$/, schema.nodes.heading, (match) => ({
            level: match[1].length,
        })),
        markInputRule(/(\*\*([^*\s][^*]*[^*\s]|[^*\s])\*\*)$/, schema.marks.strong),
        markInputRule(/(?:^|[^*])(\*([^*\s][^*]*[^*\s]|[^*\s])\*)$/, schema.marks.em),
        markInputRule(/(`([^`]+)`)$/, schema.marks.code),
    ];
    return inputRules({ rules: rules });
}
