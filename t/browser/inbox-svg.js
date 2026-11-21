// t/browser/inbox-svg.js
//
// Check that an entry containing an SVG does not break inbox controls.
//
// Authors:
//      SAPHID <saphid@users.noreply.github.com>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself. For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

"use strict";

const assert = require("node:assert/strict");
const { BASE, launch, createFixture, deleteFixture, login } = require("./lib/browser");

async function itemIsVisible(page, selector) {
    return page.$eval(selector, (element) => element.checkVisibility());
}

async function runInbox(browser, fixture, beta) {
    const page = await browser.newPage();
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.stack));
    page.on("dialog", (dialog) => dialog.dismiss());
    const { entryQid, commentQid } = fixture;
    const row = beta ? `.inbox_item_row:has(#check_${entryQid})` : `#all_Row_${entryQid}`;
    const commentRow = beta ? `.inbox_item_row:has(#check_${commentQid})` : `#all_Row_${commentQid}`;
    const content = `${row} .InboxItem_Content`;
    const expand = `${row} ${beta ? ".item_expand_action" : ".InboxItem_Expand"}`;
    const selected = beta ? "selected-msg" : "selected";
    const rpc = beta ? "/__rpc_inbox_actions" : "/__rpc_esn_inbox";
    const deleteButton = beta ? '.action_button[data-action="delete"]' : "#all_Delete_1";
    const inboxPath = beta ? "/inbox/new" : "/inbox/";

    try {
        const response = await page.goto(`${BASE}${inboxPath}?expand=${entryQid}`, {
            waitUntil: "networkidle2",
        });
        assert.equal(response.status(), 200, `${inboxPath} loads`);
        assert.equal(new URL(page.url()).pathname, inboxPath);
        assert.equal(await page.$eval(`${content} svg`, (svg) => svg.namespaceURI),
            "http://www.w3.org/2000/svg", "entry SVG reaches the DOM");
        assert.equal(await page.$(`${commentRow} .InboxItem_Content svg`), null,
            "comment cleaner removes SVG elements");
        for (const item of [row, commentRow]) {
            assert.equal(await page.$(`${item} img[src^="data:"]`), null,
                "cleaner removes data-URL image sources");
        }
        console.log(`PASS: ${inboxPath} renders the entry SVG, strips comment SVG and data-URL sources`);

        assert.deepEqual(errors, [], `${inboxPath} initializes with inline SVG`);
        assert(await itemIsVisible(page, content), `${inboxPath} starts with the entry expanded`);
        await page.click(expand);
        assert(!(await itemIsVisible(page, content)), `${inboxPath} collapses the entry`);
        await page.click(expand);
        assert(await itemIsVisible(page, content), `${inboxPath} expands the entry again`);

        await page.click(`${content} svg circle`);
        assert(await page.$eval(`${row} input[type="checkbox"]`, (input) => input.checked),
            `${inboxPath} selects the notification by clicking its SVG`);
        assert(await page.$(`${row}.${selected}`), `${inboxPath} highlights the selected notification`);

        const [deletion] = await Promise.all([
            page.waitForResponse((reply) => new URL(reply.url()).pathname === rpc &&
                reply.request().method() === "POST"),
            page.click(deleteButton),
        ]);
        assert.equal(deletion.status(), 200, `${inboxPath} deletes via the inbox RPC`);
        await page.waitForSelector(row, { hidden: true });
        assert(await page.$(commentRow), `${inboxPath} retains the unselected comment`);
        await page.reload({ waitUntil: "networkidle2" });
        assert.equal(await page.$(row), null, `${inboxPath} deletion persists after reload`);
        assert.deepEqual(errors, [], `${inboxPath} interaction has no uncaught errors`);
        console.log(`PASS: ${inboxPath} collapses, expands, selects via SVG, and deletes via RPC`);
    } finally {
        await page.close();
    }
}

(async () => {
    const browser = await launch();
    try {
        for (const beta of [true, false]) {
            const fixture = createFixture("inbox-svg");
            try {
                await browser.setCookie(...await login(browser, fixture.user, fixture.password));
                await runInbox(browser, fixture, beta);
            } finally {
                deleteFixture("inbox-svg", fixture.user);
            }
        }
    } finally {
        await browser.close();
    }
})().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
