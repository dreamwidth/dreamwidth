// src/editor/test/toolbar.test.js
//
// Toolbar behaviour: the "More" panel, which holds the groups that don't fit
// on one row, closes once a button in it is used; the table menu's header
// items act on the table's first row and column.
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
import { TextSelection } from "prosemirror-state";
import { normalized } from "./helpers.js";

const { mount, unmount, getHTML } = await import("../src/index.js");

test("a button used from the More panel closes it; a menu button leaves it open", () => {
    const textarea = document.createElement("textarea");
    textarea.id = "more-test";
    textarea.value = "<p>text</p>";
    document.body.appendChild(textarea);
    mount("more-test");

    // jsdom has no layout, so put groups in the panel the way a narrow
    // toolbar would.
    const toolbar = document.querySelector(".dw-editor-toolbar");
    const more = toolbar.querySelector(".dw-editor-more");
    const panel = toolbar.querySelector(".dw-editor-more-panel");
    const moreBtn = toolbar.querySelector(".dw-editor-more-button");
    const groupOf = (sel) => toolbar.querySelector(sel).closest(".dw-editor-toolbar-group");
    panel.appendChild(groupOf(".dw-editor-button-bullet-list"));
    panel.appendChild(groupOf(".dw-editor-dropdown-button[title='Alignment']"));
    more.hidden = false;

    moreBtn.click();
    assert.equal(panel.hidden, false);
    panel.querySelector(".dw-editor-dropdown-button[title='Alignment']").click();
    assert.equal(panel.hidden, false, "opening a menu in the panel keeps it open");

    panel.querySelector(".dw-editor-button-bullet-list").click();
    assert.equal(panel.hidden, true, "the panel closes once a button in it is used");
    assert.match(getHTML("more-test"), /<ul><li><p>text<\/p><\/li><\/ul>|<ul><li>text<\/li><\/ul>/);

    unmount("more-test");
    textarea.remove();
});

test("the table menu's header items act on the first row and column, wherever the cursor is", () => {
    const table = "<table><tbody><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></tbody></table>";
    const item = (label) =>
        Array.from(document.querySelectorAll(".dw-editor-dropdown-item")).find((b) => b.textContent == label);
    const cases = [
        ["Toggle header row", "<table><tbody><tr><th>a</th><th>b</th></tr><tr><td>c</td><td>d</td></tr></tbody></table>"],
        ["Toggle header column", "<table><tbody><tr><th>a</th><td>b</td></tr><tr><th>c</th><td>d</td></tr></tbody></table>"],
    ];
    for (const [label, expected] of cases) {
        const textarea = document.createElement("textarea");
        textarea.id = "header-test";
        textarea.value = table;
        document.body.appendChild(textarea);
        const { view } = mount("header-test");
        // The cursor in the last cell, "d".
        let at = null;
        view.state.doc.descendants((node, pos) => {
            if (node.isText && node.text == "d") at = pos + 1;
        });
        view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, at)));
        item(label).click();
        assert.equal(normalized(getHTML("header-test")), normalized(expected), label);
        unmount("header-test");
        textarea.remove();
    }
});
