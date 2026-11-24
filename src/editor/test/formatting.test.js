// Tables, alignment, indent, and text color/size: old entries' markup for
// these loads as editable content without changing what it renders as, and
// the toolbar commands write markup the cleaner keeps.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.

import test from "node:test";
import assert from "node:assert/strict";
import { EditorState, TextSelection } from "prosemirror-state";
import { addRowAfter, mergeCells, CellSelection } from "prosemirror-tables";
import { DOMParser as PMDOMParser } from "prosemirror-model";
import { schema, importHTML, exportHTML, roundTrip, normalized } from "./helpers.js";
import {
    setAlignment,
    indent,
    outdent,
    setTextStyle,
    setTextStyles,
    insertTable,
    blockAlignment,
} from "../src/commands.js";

function assertSurvives(html, message) {
    assert.equal(normalized(roundTrip(html)), normalized(html), message);
}

function stateFor(html) {
    return EditorState.create({ doc: importHTML(schema, html) });
}

function run(state, command) {
    let next = state;
    const applied = command(state, (tr) => {
        next = state.apply(tr);
    });
    assert.ok(applied, "command applies");
    return next;
}

function html(state) {
    return normalized(exportHTML(schema, state.doc));
}

// Select the text of the first occurrence of `text`.
function select(state, text) {
    let found = null;
    state.doc.descendants((node, pos) => {
        if (found == null && node.isText && node.text.indexOf(text) >= 0)
            found = pos + node.text.indexOf(text);
    });
    assert.ok(found != null, "found " + text);
    return state.apply(
        state.tr.setSelection(TextSelection.create(state.doc, found, found + text.length)),
    );
}

test("a plain table loads as an editable table and comes back the same", () => {
    const doc = importHTML(schema, "<table><tbody><tr><td>a</td><td>b</td></tr></tbody></table>");
    assert.equal(doc.firstChild.type.name, "table");
    assertSurvives(
        '<table border="1" cellpadding="4" style="width: 50%;"><tbody>' +
            '<tr class="r"><th>h1</th><th colspan="2" bgcolor="#eee">h2</th></tr>' +
            '<tr><td rowspan="2" valign="top">a <strong>b</strong></td><td>c</td><td>d</td></tr>' +
            "<tr><td>e</td><td><p>one</p><p>two</p></td></tr>" +
            "</tbody></table>",
    );
});

test("tables the editor can't hold exactly stay as HTML blocks", () => {
    [
        "<table><caption>c</caption><tr><td>x</td></tr></table>",
        "<table><thead><tr><th>h</th></tr></thead><tbody><tr><td>x</td></tr></tbody></table>",
        "<table><colgroup><col></colgroup><tr><td>x</td></tr></table>",
        // ragged rows, overlapping spans, a span past the end
        "<table><tr><td>a</td><td>b</td></tr><tr><td>c</td></tr></table>",
        '<table><tr><td rowspan="2">a</td><td>b</td></tr><tr><td colspan="2">c</td></tr></table>',
        '<table><tr><td rowspan="3">a</td></tr><tr></tr></table>',
        // a cell mixing running text and blocks
        "<table><tr><td>text<p>para</p></td></tr></table>",
    ].forEach((table) => {
        const doc = importHTML(schema, table);
        assert.equal(doc.firstChild.type.name, "html_block", table);
        assert.equal(normalized(exportHTML(schema, doc)), normalized(doc.firstChild.textContent));
    });
});

test("tables nest, and user tags in cells stay user tags", () => {
    assertSurvives(
        "<table><tbody><tr><td><table><tbody><tr><td>in</td></tr></tbody></table></td></tr></tbody></table>",
    );
    assert.match(
        roundTrip('<table><tr><td><user name="carol"> hi</td></tr></table>'),
        /<td><user name="carol"> hi<\/td>/,
    );
});

test("rows added to a table come out as plain cells", () => {
    let state = stateFor("<table><tr><td>a</td><td>b</td></tr></table>");
    state = state.apply(state.tr.setSelection(TextSelection.create(state.doc, 4)));
    state = run(state, addRowAfter);
    assert.equal(
        html(state),
        normalized(
            "<table><tbody><tr><td>a</td><td>b</td></tr><tr><td></td><td></td></tr></tbody></table>",
        ),
    );
});

test("merging cells writes a colspan", () => {
    let state = stateFor("<table><tr><td>a</td><td>b</td></tr></table>");
    const cells = [];
    state.doc.descendants((node, pos) => {
        if (node.type.name == "table_cell") cells.push(pos);
    });
    state = state.apply(state.tr.setSelection(CellSelection.create(state.doc, cells[0], cells[1])));
    state = run(state, mergeCells);
    assert.equal(
        html(state),
        normalized('<table><tbody><tr><td colspan="2"><p>a</p><p>b</p></td></tr></tbody></table>'),
    );
});

test("inserting a table puts the cursor in its first cell", () => {
    let state = stateFor("<p>before</p>");
    state = state.apply(state.tr.setSelection(TextSelection.create(state.doc, 7)));
    state = run(state, insertTable(schema, 2, 2));
    assert.equal(state.selection.$from.node(-1).type.name, "table_cell");
    assert.match(
        exportHTML(schema, state.doc),
        /<table border="1" cellpadding="4" style="border-collapse: collapse;"><tbody><tr><td><\/td><td><\/td><\/tr><tr><td><\/td><td><\/td><\/tr><\/tbody><\/table>/,
    );
});

test("alignment sets text-align and keeps the block's other styles", () => {
    let state = select(
        stateFor('<p style="border: 1px solid red;" align="right">text</p>'),
        "text",
    );
    state = run(state, setAlignment("center"));
    assert.equal(
        html(state),
        normalized('<p style="border: 1px solid red; text-align: center;">text</p>'),
    );
    state = run(state, setAlignment("left"));
    assert.equal(html(state), normalized('<p style="border: 1px solid red;">text</p>'));
});

test("indent steps the left margin, and outdent takes it back off", () => {
    let state = select(stateFor("<p>text</p>"), "text");
    state = run(state, indent(schema));
    state = run(state, indent(schema));
    assert.equal(html(state), normalized('<p style="margin-left: 80px;">text</p>'));
    state = run(state, outdent(schema));
    state = run(state, outdent(schema));
    assert.equal(html(state), normalized("<p>text</p>"));
});

test("indent in a list nests the item instead", () => {
    let state = select(stateFor("<ul><li>a</li><li>b</li></ul>"), "b");
    state = run(state, indent(schema));
    assert.equal(html(state), normalized("<ul><li>a<ul><li>b</li></ul></li></ul>"));
});

test("a color/size span loads as editable text style; other spans stay generic", () => {
    const doc = importHTML(schema, '<p><span style="color: #ff0000; font-size: 20px">x</span></p>');
    assert.equal(doc.firstChild.firstChild.marks[0].type.name, "text_style");
    assert.deepEqual(
        { ...doc.firstChild.firstChild.marks[0].attrs },
        {
            color: "#ff0000",
            background: null,
            fontSize: "20px",
        },
    );
    [
        '<p><span style="color: red; border: 1px solid;">x</span></p>',
        '<p><span class="c" style="color: red;">x</span></p>',
    ].forEach((source) => {
        assert.equal(
            importHTML(schema, source).firstChild.firstChild.marks[0].type.name,
            "html_mark",
        );
    });
});

test("a color span keeps its place relative to links and other marks", () => {
    // Color inside a link shows; outside it, the link's own color wins. Both
    // must come back the way they were.
    assertSurvives('<p><a href="/x"><span style="color: blue;">in</span></a></p>');
    assertSurvives('<p><span style="color: blue;"><a href="/x">out</a></span></p>');
    assertSurvives('<p><strong><span style="font-size: 20px;">s</span></strong></p>');
    assertSurvives(
        '<p><span style="font-size: 2em;"><span style="font-size: 2em;">big</span></span></p>',
    );
});

test("setting a color keeps the text's size, and removing both leaves plain text", () => {
    let state = select(stateFor('<p>a <span style="font-size: 20px;">sized</span> b</p>'), "sized");
    state = run(state, setTextStyle(schema, "color", "#00ff00"));
    assert.match(
        exportHTML(schema, state.doc), // jsdom writes the color as rgb(); a browser keeps it as set.
        /<span style="color: (#00ff00|rgb\(0, 255, 0\)); font-size: 20px;">sized<\/span>/,
    );
    state = run(state, setTextStyles(schema, { color: null, background: null }));
    state = run(state, setTextStyle(schema, "fontSize", null));
    assert.equal(html(state), normalized("<p>a sized b</p>"));
});

function cellSelection(state) {
    const cells = [];
    state.doc.descendants((node, pos) => {
        if (node.type.name == "table_cell") cells.push(pos);
    });
    return state.apply(
        state.tr.setSelection(CellSelection.create(state.doc, cells[0], cells[cells.length - 1])),
    );
}

test("a table that keeps its whitespace stays an HTML block", () => {
    const doc = importHTML(
        schema,
        '<table><tr><td style="white-space: pre-wrap;">a   b\nc</td></tr></table>',
    );
    assert.equal(doc.firstChild.type.name, "html_block");
});

test("formatting the editor wrote survives being copied and pasted back in", () => {
    // Pasted markup is parsed directly, without the import pre-pass.
    const source =
        '<table border="1" cellpadding="4"><tbody><tr><td style="width: 5em;">x</td></tr></tbody></table>' +
        '<p style="text-align: center; margin-left: 40px;">' +
        '<span style="color: red; font-size: 20px;">styled</span></p>';
    const tpl = document.createElement("template");
    tpl.innerHTML = source;
    const doc = PMDOMParser.fromSchema(schema).parse(tpl.content);
    assert.equal(normalized(exportHTML(schema, doc)), normalized(source));
});

test("a span whose CSS relies on priority or repeats stays as it was", () => {
    [
        '<p><span style="color: red !important; color: blue;">X</span></p>',
        '<p><span style="color: red; color: blue;">X</span></p>',
    ].forEach((source) => {
        const doc = importHTML(schema, source);
        const mark = doc.firstChild.firstChild.marks[0];
        assert.equal(mark.type.name, "html_mark", source);
        // (Checked on the stored attribute: jsdom, unlike a browser, rewrites
        // a style attribute set from script.)
        assert.equal(mark.attrs.extra.style, /style="([^"]*)"/.exec(source)[1]);
    });
});

test("recoloring text inside an old colored span replaces the old color", () => {
    let state = select(stateFor('<p><strong><span style="color: red;">X</span></strong></p>'), "X");
    state = run(state, setTextStyle(schema, "color", "#00ff00"));
    assert.doesNotMatch(exportHTML(schema, state.doc), /red/);
    state = run(state, setTextStyles(schema, { color: null, background: null }));
    assert.equal(html(state), normalized("<p><strong>X</strong></p>"));

    state = select(stateFor('<p><font color="red" face="serif">Y</font></p>'), "Y");
    state = run(state, setTextStyles(schema, { color: null, background: null }));
    assert.equal(html(state), normalized('<p><font face="serif">Y</font></p>'));
});

test("alignment and indent apply to every selected cell", () => {
    let state = cellSelection(
        stateFor("<table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>"),
    );
    state = run(state, setAlignment("center"));
    assert.equal((exportHTML(schema, state.doc).match(/text-align: center/g) || []).length, 4);
});

test("a table can't be inserted over selected cells", () => {
    const state = cellSelection(stateFor("<table><tr><td>a</td><td>b</td></tr></table>"));
    assert.equal(insertTable(schema, 1, 1)(state), false);
});

test("unindent never lifts text out of a cut tag", () => {
    const state = select(stateFor('<cut text="Spoilers"><p>secret</p></cut>'), "secret");
    assert.equal(
        outdent(schema)(state, () => assert.fail("dispatched")),
        false,
    );
});

test("align left inside a centered block sets left explicitly", () => {
    let state = select(stateFor('<div style="text-align: center;"><p>X</p></div>'), "X");
    assert.equal(blockAlignment(state), "center");
    state = run(state, setAlignment("left"));
    assert.match(exportHTML(schema, state.doc), /<p style="text-align: left;">X<\/p>/);
    assert.equal(blockAlignment(state), "left");
});
