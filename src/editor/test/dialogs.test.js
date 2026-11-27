// src/editor/test/dialogs.test.js
//
// The editor's small form dialogs in browsers without <dialog> support
// (jsdom has none either): they must still open, return what was entered,
// and never submit the entry form they sit beside.
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

const { linkDialog } = await import("../src/dialogs.js");
const strings = { linkTitle: "Add link", linkUrl: "URL", ok: "OK", cancel: "Cancel" };

test("without <dialog> support, a dialog opens and returns what was entered", async () => {
    assert.equal(typeof document.createElement("dialog").showModal, "undefined");
    const result = linkDialog(strings, "");
    const dialog = document.querySelector(".dw-editor-dialog");
    assert.ok(dialog.hasAttribute("open"));
    dialog.querySelector("input").value = "https://example.com/";
    const submit = new window.Event("submit", { cancelable: true });
    dialog.querySelector("form").dispatchEvent(submit);
    assert.ok(submit.defaultPrevented, "the page isn't submitted");
    assert.equal(await result, "https://example.com/");
    assert.equal(document.querySelector(".dw-editor-dialog, .dw-editor-dialog-backdrop"), null);
});

test("without <dialog> support, Cancel and Escape close it with nothing", async () => {
    let result = linkDialog(strings, "");
    document.querySelector(".dw-editor-dialog button[type=button]").click();
    assert.equal(await result, null);
    result = linkDialog(strings, "");
    document
        .querySelector(".dw-editor-dialog")
        .dispatchEvent(new window.KeyboardEvent("keydown", { key: "Escape", cancelable: true }));
    assert.equal(await result, null);
});
