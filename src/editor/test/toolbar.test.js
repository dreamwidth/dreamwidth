// src/editor/test/toolbar.test.js
//
// The toolbar's "More" panel, which holds the groups that don't fit on one
// row: using a button from it closes it, so it doesn't stay over the text.
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
import "./helpers.js";

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
