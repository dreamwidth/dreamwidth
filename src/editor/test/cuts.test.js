// src/editor/test/cuts.test.js
//
// Cut tags that start or end partway through a paragraph: loading them
// without letting hidden text out, saving them back as they were written,
// and making and unmaking them in the editor.
//
// Authors:
//     Mark Smith <mark@qq.is>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself.  For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

import test from "node:test";
import assert from "node:assert/strict";
import { EditorState, TextSelection } from "prosemirror-state";
import { schema, importHTML, exportHTML, roundTrip } from "./helpers.js";
import { insertCut, unjoinCut, cutJoins } from "../src/commands.js";

// What's behind each cut in a document, as text.
function hidden(doc) {
    const out = [];
    doc.descendants((node) => {
        if (node.type.name == "cut") out.push(node.textContent);
        return true;
    });
    return out;
}

// Compared as exact text: these shapes aren't trees, so they can't be
// normalized by parsing them.
test("cuts starting or ending partway through a paragraph save as written", () => {
    [
        '<p>Visible, and then <cut text="More">hidden.</cut></p>',
        '<p>Visible <cut text="More">hidden</cut> visible again.</p>',
        '<p><cut text="More">hidden</cut> visible.</p>',
        '<p>Visible, and then <cut text="More">hidden.</p><p>Also hidden.</p></cut>',
        '<p>a <cut text="x">b</p><p>c</cut> d</p>',
        '<p>a <cut text="1">b <cut text="2">c</cut> d</cut> e</p>',
        '<p>a <cut text="x>y">b</cut></p>',
    ].forEach((html) => assert.equal(roundTrip(html), html));
});

test("hidden paragraphs after a cut's first paragraph stay hidden", () => {
    // A browser would end this cut at the first </p>.
    const doc = importHTML(
        schema,
        '<p>Visible <cut text="More">hidden one.</p><p>hidden two.</p></cut><p>Shown.</p>'
    );
    assert.deepEqual(hidden(doc), ["hidden one.hidden two."]);
    assert.equal(doc.lastChild.textContent, "Shown.");
});

test("a cut in loose text joins the text around it", () => {
    const html =
        'Visible, then <cut text="More">hidden.<br><br>Hidden too.</cut><br><br>Visible again.';
    const doc = importHTML(schema, html);
    assert.deepEqual(hidden(doc), ["hidden.Hidden too."]);
    assert.equal(
        exportHTML(schema, doc),
        '<p>Visible, then <cut text="More">hidden.<br><br>Hidden too.</cut><br><br>Visible again.</p>'
    );
});

test("a cut with no closing tag hides the rest, and a stray closing tag is dropped", () => {
    assert.deepEqual(hidden(importHTML(schema, "<p>a <cut>b</p><p>c</p>")), ["bc"]);
    assert.equal(hidden(importHTML(schema, "<p>a </cut> b</p>")).length, 0);
});

test("cut tags in comments and raw text are left alone", () => {
    const html = "<pre>&lt;cut&gt;</pre><textarea><cut>x</cut></textarea>";
    assert.equal(hidden(importHTML(schema, html)).length, 0);
});

function stateAt(html, text, length) {
    const state = EditorState.create({ doc: importHTML(schema, html), plugins: [cutJoins(schema)] });
    let at = null;
    state.doc.descendants((node, pos) => {
        if (at == null && node.isText && node.text.indexOf(text) >= 0) at = pos + node.text.indexOf(text);
    });
    return state.apply(state.tr.setSelection(TextSelection.create(state.doc, at, at + (length || 0))));
}

function run(state, command) {
    let next = state;
    assert.ok(command(state, (tr) => (next = next.applyTransaction(tr).state)), "command applies");
    return next;
}

test("the Cut button starts a cut where the cursor is", () => {
    const state = run(stateAt("<p>Visible part. Hidden part.</p>", "Hidden"), insertCut(schema));
    assert.equal(exportHTML(schema, state.doc), "<p>Visible part. <cut>Hidden part.</cut></p>");
    assert.deepEqual(hidden(state.doc), ["Hidden part."]);
});

test("the Cut button hides just the selected words of a paragraph", () => {
    const state = run(stateAt("<p>Before secret after.</p>", "secret", 6), insertCut(schema));
    assert.equal(exportHTML(schema, state.doc), "<p>Before <cut>secret</cut> after.</p>");
});

test("the Cut button wraps whole blocks from the start of a paragraph", () => {
    const state = run(stateAt("<p>All of this.</p>", "All"), insertCut(schema));
    assert.equal(exportHTML(schema, state.doc), "<cut><p>All of this.</p></cut>");
});

test("Backspace at the start of a joined cut separates it", () => {
    // At the start of the hidden text: it no longer continues "Shown".
    let state = run(stateAt('<p>Shown <cut text="x">secret</cut> rest</p>', "secret"), unjoinCut(schema));
    assert.equal(exportHTML(schema, state.doc), '<p>Shown</p>\n\n<p><cut text="x">secret</cut> rest</p>');
    // At the start of the text after it: that becomes its own paragraph.
    state = run(stateAt('<p>Shown <cut text="x">secret</cut> rest</p>', "rest"), unjoinCut(schema));
    assert.equal(exportHTML(schema, state.doc), '<p>Shown <cut text="x">secret</cut></p>\n\n<p>rest</p>');
});

test("a cut whose paragraph is changed stops being joined to it", () => {
    const state = stateAt('<p>first</p><p>visible <cut text="x">secret</cut></p>', "visible");
    const $at = state.selection.$from;
    const next = state.applyTransaction(
        state.tr.setBlockType($at.before(), $at.after(), schema.nodes.heading, { level: 2 })
    ).state;
    assert.equal(next.doc.child(2).attrs.lead, false);
    assert.match(exportHTML(schema, next.doc), /<h2>visible<\/h2>\s*<cut text="x"><p>secret<\/p><\/cut>/);
});
