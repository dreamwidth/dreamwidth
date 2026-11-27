// src/editor/src/commands.js
//
// Editing commands behind the formatting toolbar: alignment, indent, text
// colour/highlight/size, and table insertion. Each follows ProseMirror's
// command convention: (state, dispatch?) -> whether it applies, doing it
// when dispatch is given.
//
// Authors:
//     Mark Smith <mark@qq.is>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself.  For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

import { lift, wrapIn } from "prosemirror-commands";
import { sinkListItem, liftListItem } from "prosemirror-schema-list";
import { TextSelection, Plugin, PluginKey } from "prosemirror-state";
import { Mark } from "prosemirror-model";
import { CellSelection } from "prosemirror-tables";
import { extraWithStyle, styleOfExtra, getStyleProp } from "./style.js";

// Blocks alignment and indent apply to: anything holding a line of text.
const TEXT_BLOCKS = ["paragraph", "heading", "html_textblock"];

// One indent step, the same as the old editor's.
const INDENT_STEP = 40;

// The text blocks in the selection. A selection of table cells has a range
// per cell.
function styledBlocks(state) {
    const found = [];
    const seen = new Set();
    state.selection.ranges.forEach((range) => {
        state.doc.nodesBetween(range.$from.pos, range.$to.pos, (node, pos) => {
            if (TEXT_BLOCKS.indexOf(node.type.name) < 0) return true;
            if (!seen.has(pos)) {
                seen.add(pos);
                found.push({ node, pos });
            }
            return false;
        });
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
        const value = update(current, node, pos);
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

// A node's own alignment: text-align in its style, an old align="..."
// attribute (which on a table places the table rather than its text), or
// <center>.
// Only the four the toolbar sets count; anything else (inherit, start, ...)
// leaves it to what's around. Right-to-left text starts on the right.
const ALIGNMENTS = ["left", "center", "right", "justify"];

function ownAlignment(node) {
    const extra = node.attrs.extra;
    const candidates = [getStyleProp(styleOfExtra(extra), "text-align")];
    if (extra && node.type.name != "table") candidates.push(extra.align);
    if (node.attrs.tag == "center") candidates.push("center");
    for (const value of candidates) {
        const align = String(value || "").toLowerCase();
        if (ALIGNMENTS.indexOf(align) >= 0) return align;
    }
    if (extra && String(extra.dir || "").toLowerCase() == "rtl") return "right";
    return null;
}

// The alignment a block at pos inherits from what it sits in.
function inheritedAlignment(doc, pos) {
    const $pos = doc.resolve(pos);
    for (let d = $pos.depth; d > 0; d--) {
        const value = ownAlignment($pos.node(d));
        if (value) return value;
    }
    return "left";
}

// The alignment of the block the cursor is in.
export function blockAlignment(state) {
    const { $from } = state.selection;
    if (TEXT_BLOCKS.indexOf($from.parent.type.name) < 0) return null;
    return ownAlignment($from.parent) || inheritedAlignment(state.doc, $from.before());
}

// value: left, center, right or justify. Left is the default, so it removes
// the setting -- unless the block would then inherit another alignment, when
// it's set explicitly. An old align="..." attribute is replaced either way.
export function setAlignment(value) {
    return (state, dispatch) => {
        if (!styledBlocks(state).length) return false;
        if (!dispatch) return true;
        updateBlockStyle(
            state,
            dispatch,
            "text-align",
            (current, node, pos) => {
                if (value != "left") return value;
                // Left is the default unless something says otherwise.
                const extra = node.attrs.extra;
                const rtl = extra && String(extra.dir || "").toLowerCase() == "rtl";
                return rtl || inheritedAlignment(state.doc, pos) != "left" ? "left" : null;
            },
            ["align"],
        );
        return true;
    };
}

function marginPx(value) {
    if (value == null) return 0;
    const m = /^(\d+(?:\.\d+)?)px$/i.exec(String(value).trim());
    return m ? +m[1] : null;
}

// Is the cursor in a list item, and not in a table inside one? (Indent and
// Tab act on whichever is nearer.)
export function inList(state, schema) {
    const { $from } = state.selection;
    for (let d = $from.depth; d > 0; d--) {
        const type = $from.node(d).type;
        if (type == schema.nodes.list_item) return true;
        if (type.spec.tableRole == "cell" || type.spec.tableRole == "header_cell") return false;
    }
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
// both, lift the block out of whatever wraps it (a quote, ...) -- but never out
// of a cut tag, which would put its hidden text on show.
export function outdent(schema) {
    const liftItem = liftListItem(schema.nodes.list_item);
    return (state, dispatch) => {
        if (inList(state, schema)) return liftItem(state, dispatch);
        const unindented = updateBlockStyle(state, dispatch, "margin-left", (current) => {
            const px = marginPx(current);
            if (!px) return undefined;
            return px - INDENT_STEP > 0 ? px - INDENT_STEP + "px" : null;
        });
        if (unindented) return true;
        const { $from, $to } = state.selection;
        const range = $from.blockRange($to);
        if (range && range.parent.type == schema.nodes.cut) return false;
        return lift(state, dispatch);
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

// What each text-style attribute is in an old entry's own markup: the CSS
// property, and the attribute <font> uses for it.
const OLD_MARKUP = {
    color: { prop: "color", fontAttr: "color" },
    background: { prop: "background-color", fontAttr: null },
    fontSize: { prop: "font-size", fontAttr: "size" },
};

// An old entry's span or font may set the same thing the toolbar is setting,
// and one nested inside the new style would still win. Return the marks with
// that setting taken off such a span or font (one left with no attributes is
// dropped), in the same order.
function withoutOldSettings(marks, schema, changes) {
    const out = [];
    marks.forEach((mark) => {
        if (mark.type != schema.marks.html_mark && mark.type != schema.marks.html_mark_inner)
            return out.push(mark);
        let extra = mark.attrs.extra;
        Object.keys(changes).forEach((name) => {
            const old = OLD_MARKUP[name];
            if (!old || extra === undefined) return;
            extra = extraWithStyle(
                extra,
                old.prop,
                null,
                mark.attrs.tag == "font" && old.fontAttr ? [old.fontAttr] : [],
            );
        });
        if (extra === undefined || JSON.stringify(extra) == JSON.stringify(mark.attrs.extra))
            return out.push(mark);
        const tag = mark.attrs.tag;
        if (extra || (tag != "span" && tag != "font")) out.push(mark.type.create({ tag, extra }));
    });
    return out;
}

// The marks text should have once changes are applied to its text style.
function styledMarks(marks, schema, changes) {
    const type = schema.marks.text_style;
    const current = type.isInSet(marks);
    const attrs = Object.assign({}, NO_STYLE, current && current.attrs, changes);
    const rest = type.removeFromSet(withoutOldSettings(marks, schema, changes));
    return hasStyle(attrs) ? type.create(attrs).addToSet(rest) : rest;
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
            tr.setStoredMarks(styledMarks(state.storedMarks || $from.marks(), schema, changes));
        } else {
            state.selection.ranges.forEach((range) => {
                const from = range.$from.pos;
                const to = range.$to.pos;
                state.doc.nodesBetween(from, to, (node, pos, parent) => {
                    if (!node.isText) return true;
                    if (!parent.type.allowsMarkType(type)) return false;
                    const start = Math.max(pos, from);
                    const end = Math.min(pos + node.nodeSize, to);
                    const marks = styledMarks(node.marks, schema, changes);
                    // Swapping the text for itself with the new marks keeps
                    // their order (removing and re-adding one would move it).
                    // The size is unchanged, so later positions still hold.
                    if (!Mark.sameSet(marks, node.marks))
                        tr.replaceWith(
                            start,
                            end,
                            schema.text(node.text.slice(start - pos, end - pos), marks),
                        );
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
        // Over selected cells it would replace their contents.
        if (state.selection instanceof CellSelection || $from.parent.type.spec.code) return false;
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

// ---- Cut tags ------------------------------------------------------------

// The Cut button. Inside a paragraph it starts the cut where the cursor is:
// the text before stays visible, with the cut joined to it ("lead"), and the
// text after goes behind the cut. With text selected in one paragraph, just
// that text goes behind it, and the rest of the paragraph after the cut is
// joined to it too ("tail"). Anywhere else -- an empty line, the start of a
// paragraph, a selection over several blocks -- the blocks are wrapped in a
// cut of their own, as before.
export function insertCut(schema) {
    const wrap = wrapIn(schema.nodes.cut);
    return (state, dispatch) => {
        const { $from, $to, empty } = state.selection;
        const para = $from.parent;
        const inOne =
            para.type == schema.nodes.paragraph && $from.sameParent($to) && para.content.size > 0;
        const start = $from.start();
        const end = $from.end();
        const lead = inOne && $from.pos > start;
        const tail = inOne && !empty && $to.pos < end;
        if (!lead) return wrap(state, dispatch);
        // A cut can only go where a block can.
        const $para = state.doc.resolve($from.before());
        if (!$para.parent.canReplaceWith($para.index(), $para.index(), schema.nodes.cut))
            return false;
        if (!dispatch) return true;

        const tr = state.tr;
        if (tail) tr.split($to.pos);
        tr.split($from.pos);
        // The middle piece is the paragraph now starting after $from.
        const $inside = tr.doc.resolve($from.pos + 2);
        const range = $inside.blockRange();
        // The hidden piece is plain text in the cut; the visible pieces keep
        // the paragraph's attributes, and rejoin around it when saved.
        tr.setNodeMarkup(range.start, schema.nodes.paragraph);
        tr.wrap(range, [{ type: schema.nodes.cut, attrs: { lead: true, tail } }]);
        tr.setSelection(TextSelection.create(tr.doc, $from.pos + 3));
        dispatch(tr.scrollIntoView());
        return true;
    };
}

// Backspace at the start of what a cut is joined to undoes the join: at the
// start of the cut's text, it stops continuing the paragraph above; at the
// start of the paragraph after a tail-joined cut, that paragraph stands alone.
export function unjoinCut(schema) {
    const cutType = schema.nodes.cut;
    return (state, dispatch) => {
        const { $from, empty } = state.selection;
        if (!empty || $from.parentOffset > 0) return false;
        // The paragraph right after a tail-joined cut.
        const index = $from.index($from.depth - 1);
        const container = $from.node($from.depth - 1);
        const prev = index > 0 ? container.child(index - 1) : null;
        if (prev && prev.type == cutType && prev.attrs.tail) {
            if (dispatch) {
                const pos = $from.before() - prev.nodeSize;
                dispatch(state.tr.setNodeMarkup(pos, null, Object.assign({}, prev.attrs, { tail: false, tailSpace: false })));
            }
            return true;
        }
        // The first textblock of a lead-joined cut.
        for (let d = $from.depth - 1; d > 0; d--) {
            if ($from.index(d) != 0) return false;
            const node = $from.node(d);
            if (node.type == cutType) {
                if (!node.attrs.lead) return false;
                if (dispatch) {
                    const attrs = Object.assign({}, node.attrs, { lead: false, leadSpace: false });
                    dispatch(state.tr.setNodeMarkup($from.before(d), null, attrs));
                }
                return true;
            }
        }
        return false;
    };
}

// A cut can only be joined to a paragraph beside it. When editing takes that
// paragraph away (deletes it, turns it into a heading, moves the cut), the
// join is dropped.
export function cutJoins(schema) {
    const cutType = schema.nodes.cut;
    const para = schema.nodes.paragraph;
    return new Plugin({
        key: new PluginKey("cutJoins"),
        appendTransaction(transactions, oldState, newState) {
            if (!transactions.some((tr) => tr.docChanged)) return null;
            let tr = null;
            newState.doc.descendants((node, pos, parent, index) => {
                if (node.type != cutType || !(node.attrs.lead || node.attrs.tail)) return true;
                const before = index > 0 ? parent.child(index - 1) : null;
                const after = index + 1 < parent.childCount ? parent.child(index + 1) : null;
                const lead = node.attrs.lead && !!before && before.type == para;
                const tail = node.attrs.tail && !!after && after.type == para;
                if (lead != node.attrs.lead || tail != node.attrs.tail) {
                    tr = tr || newState.tr;
                    tr.setNodeMarkup(pos, null, Object.assign({}, node.attrs, {
                        lead,
                        tail,
                        leadSpace: lead && node.attrs.leadSpace,
                        tailSpace: tail && node.attrs.tailSpace,
                    }));
                }
                return true;
            });
            // Part of the edit that caused it, so undoing that brings the join back.
            return tr;
        },
    });
}
