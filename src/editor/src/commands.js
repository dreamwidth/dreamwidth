// Editing commands behind the formatting toolbar: alignment, indent, text
// colour/highlight/size, and table insertion. Each follows ProseMirror's
// command convention: (state, dispatch?) -> whether it applies, doing it
// when dispatch is given.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.

import { lift } from "prosemirror-commands";
import { sinkListItem, liftListItem } from "prosemirror-schema-list";
import { TextSelection } from "prosemirror-state";
import { extraWithStyle, styleOfExtra, getStyleProp } from "./style.js";

// Blocks alignment and indent apply to: anything holding a line of text.
const TEXT_BLOCKS = ["paragraph", "heading", "html_textblock"];

// One indent step, the same as the old editor's.
const INDENT_STEP = 40;

function styledBlocks(state) {
    const found = [];
    const { from, to } = state.selection;
    state.doc.nodesBetween(from, to, (node, pos) => {
        if (TEXT_BLOCKS.indexOf(node.type.name) >= 0) {
            found.push({ node, pos });
            return false;
        }
        return true;
    });
    return found;
}

// Rewrite a style property on every text block in the selection. update gets
// the block's current value and returns the new one (null to remove it, or
// undefined to leave that block alone).
function updateBlockStyle(state, dispatch, prop, update, alsoRemove) {
    const blocks = styledBlocks(state);
    const tr = state.tr;
    let changed = false;
    blocks.forEach(({ node, pos }) => {
        const current = getStyleProp(styleOfExtra(node.attrs.extra), prop);
        const value = update(current, node);
        if (value === undefined) return;
        const extra = extraWithStyle(node.attrs.extra, prop, value, alsoRemove);
        if (extra === undefined) return;
        tr.setNodeMarkup(pos, null, Object.assign({}, node.attrs, { extra }));
        changed = true;
    });
    if (!changed) return false;
    if (dispatch) dispatch(tr.scrollIntoView());
    return true;
}

// The alignment of the block the cursor is in: its text-align, or an old
// align="..." attribute.
export function blockAlignment(state) {
    const parent = state.selection.$from.parent;
    if (TEXT_BLOCKS.indexOf(parent.type.name) < 0) return null;
    const extra = parent.attrs.extra;
    const value = getStyleProp(styleOfExtra(extra), "text-align") || (extra && extra.align);
    return value ? String(value).toLowerCase() : "left";
}

// value: left, center, right or justify. Left is the default, so it removes
// the setting. An old align="..." attribute is replaced either way.
export function setAlignment(value) {
    return (state, dispatch) => {
        if (!styledBlocks(state).length) return false;
        if (!dispatch) return true;
        updateBlockStyle(state, dispatch, "text-align", () => (value == "left" ? null : value), [
            "align",
        ]);
        return true;
    };
}

function marginPx(value) {
    if (value == null) return 0;
    const m = /^(\d+(?:\.\d+)?)px$/i.exec(String(value).trim());
    return m ? +m[1] : null;
}

function inList(state, schema) {
    const { $from } = state.selection;
    for (let d = $from.depth; d > 0; d--)
        if ($from.node(d).type == schema.nodes.list_item) return true;
    return false;
}

// In a list, indent nests the item. Elsewhere it adds a step of left margin
// to each block (a margin in some other unit is left as it is).
export function indent(schema) {
    const sink = sinkListItem(schema.nodes.list_item);
    return (state, dispatch) => {
        if (inList(state, schema)) return sink(state, dispatch);
        return updateBlockStyle(state, dispatch, "margin-left", (current) => {
            const px = marginPx(current);
            return px == null ? undefined : px + INDENT_STEP + "px";
        });
    };
}

// The reverse: un-nest a list item, take a step of margin off, or failing
// both, lift the block out of whatever wraps it (a quote, ...).
export function outdent(schema) {
    const liftItem = liftListItem(schema.nodes.list_item);
    return (state, dispatch) => {
        if (inList(state, schema)) return liftItem(state, dispatch);
        const unindented = updateBlockStyle(state, dispatch, "margin-left", (current) => {
            const px = marginPx(current);
            if (!px) return undefined;
            return px - INDENT_STEP > 0 ? px - INDENT_STEP + "px" : null;
        });
        return unindented || lift(state, dispatch);
    };
}

// ---- Text colour, highlight, size ----------------------------------------

const NO_STYLE = { color: null, background: null, fontSize: null };

function hasStyle(attrs) {
    return !!(attrs.color || attrs.background || attrs.fontSize);
}

export function currentTextStyle(state, schema) {
    const type = schema.marks.text_style;
    const { $from, empty } = state.selection;
    const marks = empty
        ? state.storedMarks || $from.marks()
        : $from.marksAcross(state.selection.$to) || $from.marks();
    const mark = type.isInSet(marks || []);
    return mark ? mark.attrs : NO_STYLE;
}

// Set text-style attributes (color, background, fontSize) on the selection,
// keeping the others each piece of text already has. changes maps attribute
// names to values; a null value removes that one.
export function setTextStyle(schema, name, value) {
    return setTextStyles(schema, { [name]: value });
}

export function setTextStyles(schema, changes) {
    const type = schema.marks.text_style;
    return (state, dispatch) => {
        const { $from, empty } = state.selection;
        if (empty && $from.parent.type.spec.code) return false;
        if (!dispatch) return true;

        const tr = state.tr;
        if (empty) {
            const marks = state.storedMarks || $from.marks();
            const current = type.isInSet(marks);
            const attrs = Object.assign({}, NO_STYLE, current && current.attrs, changes);
            tr.removeStoredMark(type);
            if (hasStyle(attrs)) tr.addStoredMark(type.create(attrs));
        } else {
            state.selection.ranges.forEach((range) => {
                const from = range.$from.pos;
                const to = range.$to.pos;
                state.doc.nodesBetween(from, to, (node, pos, parent) => {
                    if (!node.isText) return true;
                    if (!parent.type.allowsMarkType(type)) return false;
                    const start = Math.max(pos, from);
                    const end = Math.min(pos + node.nodeSize, to);
                    const current = type.isInSet(node.marks);
                    const attrs = Object.assign({}, NO_STYLE, current && current.attrs, changes);
                    if (hasStyle(attrs)) tr.addMark(start, end, type.create(attrs));
                    else tr.removeMark(start, end, type);
                    return false;
                });
            });
        }
        dispatch(tr.scrollIntoView());
        return true;
    };
}

// ---- Tables --------------------------------------------------------------

// A new table gets visible borders; without them it doesn't show at all once
// posted. They're ordinary attributes, so they can be changed in HTML.
const NEW_TABLE = { border: "1", cellpadding: "4", style: "border-collapse: collapse;" };

export function insertTable(schema, rows, cols) {
    return (state, dispatch) => {
        const { $from } = state.selection;
        if ($from.parent.type.spec.code) return false;
        if (!dispatch) return true;
        const { table, table_row, table_cell, paragraph } = schema.nodes;
        const rowNodes = [];
        for (let r = 0; r < rows; r++) {
            const cells = [];
            for (let c = 0; c < cols; c++) cells.push(table_cell.create(null, paragraph.create()));
            rowNodes.push(table_row.create(null, cells));
        }
        const tr = state.tr.replaceSelectionWith(table.create({ extra: NEW_TABLE }, rowNodes));
        // Put the cursor in the first cell of the table just inserted: the
        // first table starting at or after where the replacement began (any
        // table around the cursor starts before it).
        const start = tr.steps.length ? tr.steps[tr.steps.length - 1].from : $from.pos;
        let target = null;
        tr.doc.nodesBetween(start, tr.doc.content.size, (node, pos) => {
            if (target != null) return false;
            if (node.type == table && pos >= start) {
                target = pos + 4; // table > row > cell > paragraph
                return false;
            }
            return true;
        });
        if (target != null) tr.setSelection(TextSelection.create(tr.doc, target));
        dispatch(tr.scrollIntoView());
        return true;
    };
}
