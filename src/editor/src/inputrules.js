// Markdown-style typing shortcuts, so muscle memory from the Markdown format
// keeps working in the rich editor: **bold**, *em*, `code`, # headings,
// > quotes, - lists, ``` code blocks. These only affect what's typed; the
// stored format is still explicit HTML.

import {
    inputRules,
    wrappingInputRule,
    textblockTypeInputRule,
    InputRule,
} from "prosemirror-inputrules";

// Apply a mark to the text matched by group 2, deleting the delimiters
// (the classic markInputRule helper).
function markInputRule(regexp, markType) {
    return new InputRule(regexp, (state, match, start, end) => {
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
