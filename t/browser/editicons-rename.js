// t/browser/editicons-rename.js
//
// Check that icon keyword renaming is discoverable and usable on the rendered
// management page, with and without page JavaScript. Uses the Chrome and
// puppeteer-core setup described in doc/SCREENSHOTS.md.
//
// Authors:
//      SAPHID <saphid@users.noreply.github.com>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself. For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.
//
// Run inside the devcontainer against a disposable account with an active icon,
// icon renames enabled, and mapped keywords (dversion >= 9):
//   DW_ICON_TEST_COOKIES=/tmp/icon-test-cookies.json node t/browser/editicons-rename.js
// The cookie file is a JSON array of Puppeteer cookies for the target origin.
// DW_ICON_TEST_URL can override the default local management-page URL.
// This test changes only unsaved checkbox state; it never submits a form.

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const puppeteer = require("/opt/dw-screenshot/node_modules/puppeteer-core");

async function checkPage(browser, cookies, javaScriptEnabled, width) {
    const page = await browser.newPage();
    try {
        await page.setViewport({ width, height: 1000 });
        await page.setJavaScriptEnabled(javaScriptEnabled);
        await page.setCookie(...cookies);
        const response = await page.goto(
            process.env.DW_ICON_TEST_URL || "http://127.0.0.1:8080/manage/icons",
            { waitUntil: "networkidle2", timeout: 30000 }
        );
        assert.equal(response.status(), 200, "management page loads");

        const ids = await page.$$eval(
            '#current_userpics input[name^="rename_keyword_"]:not(:disabled)',
            inputs => inputs.map(input => input.id)
        );
        assert.ok(ids.length, "fixture has an enabled rename checkbox; check login and feature gate");

        // Check every icon before focusing any keyword field. A source-text
        // assertion cannot detect the script hiding these controls on load.
        for (const id of ids) {
            const checkbox = await page.$("#" + id);
            const box = await checkbox.boundingBox();
            assert.ok(box && box.width > 0 && box.height > 0, id + " is visible before focus");
            const label = await page.$('label[for="' + id + '"]');
            assert.ok(label, id + " has an associated label");
            const labelBox = await label.boundingBox();
            assert.ok(labelBox && labelBox.width > 0, id + " label is visible");
        }

        const id = ids[0];
        const selector = "#" + id;
        const state = () => page.$eval(selector, input => ({
            checked: input.checked,
            focused: document.activeElement === input,
            submitted: new FormData(input.form).get(input.name)
        }));
        assert.equal((await state()).checked, false, "renaming is opt-in");

        // Clicking the label must toggle the checkbox without first editing
        // keywords, and the real form must send the controller's expected value.
        await page.click('label[for="' + id + '"]');
        assert.deepEqual(await state(), { checked: true, focused: true, submitted: "1" });
        await page.keyboard.press("Space");
        assert.deepEqual(await state(), { checked: false, focused: true, submitted: null });

        // The checkbox must be reachable in the natural keyboard tab order.
        const picid = id.slice("rename_keyword_".length);
        await page.focus("#kw_" + picid);
        await page.keyboard.press("Tab");
        assert.equal((await state()).focused, true, "Tab reaches the rename option");
        await page.keyboard.press("Space");
        assert.deepEqual(await state(), { checked: true, focused: true, submitted: "1" });
        await page.keyboard.press("Space");
        assert.equal((await state()).submitted, null, "unchecked rename option is not submitted");

        console.log("PASS: icon rename, JS=" + javaScriptEnabled + ", width=" + width);
    } finally {
        await page.close();
    }
}

(async () => {
    assert.ok(process.env.DW_ICON_TEST_COOKIES, "set DW_ICON_TEST_COOKIES to a private cookie file");
    const cookies = JSON.parse(fs.readFileSync(process.env.DW_ICON_TEST_COOKIES, "utf8"));
    assert.ok(Array.isArray(cookies) && cookies.length, "cookie file contains a signed-in session");
    const browser = await puppeteer.launch({
        executablePath: "/usr/bin/google-chrome-stable",
        args: ["--no-sandbox", "--disable-gpu"],
        defaultViewport: { width: 1280, height: 1000 }
    });
    try {
        for (const javaScriptEnabled of [true, false]) {
            for (const width of [1280, 390]) {
                await checkPage(browser, cookies, javaScriptEnabled, width);
            }
        }
    } finally {
        await browser.close();
    }
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
