// t/browser/entry-custom-security.js
//
// Use the entry form with only keyboard input, and inspect the stored access
// mask after submitting with and without page JavaScript.
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
const { execFileSync } = require("node:child_process");
const path = require("node:path");
const { BASE, launch, createFixture, deleteFixture, login } = require("./lib/browser");

const fixtureName = "entry-custom-security";
const security = "#js-security";
const post = 'input[name="action:post"]';

async function tabTo(page, selector) {
    for (let count = 0; count < 100; count++) {
        if (await page.evaluate(selector => document.activeElement.matches(selector), selector)) return;
        await page.keyboard.press("Tab");
    }
    assert.fail("Could not reach " + selector + " by tabbing");
}

async function checkPosting(browser, cookies, fixture, javaScript) {
    const page = await browser.newPage();
    try {
        const subject = javaScript ? "Keyboard custom access" : "No JavaScript custom access";
        await page.setJavaScriptEnabled(javaScript);
        await page.setCookie(...cookies);
        const response = await page.goto(BASE + "/entry/new", { waitUntil: "networkidle2" });
        assert.equal(response.status(), 200, "entry form loads");

        await tabTo(page, '[name="subject"]');
        await page.keyboard.type(subject);
        await tabTo(page, '[name="event"]');
        await page.keyboard.type("Synthetic browser regression entry");
        await tabTo(page, security);
        await page.keyboard.press("End");
        assert.equal(await page.$eval(security, select => select.value), "custom");

        const [first, , last] = fixture.bits.map(bit => `#custom-bit-${bit}`);
        assert.ok(await page.waitForSelector(first, { visible: true, timeout: 2500 }),
            "selecting Custom offers the access groups");
        for (const group of [first, last]) {
            await tabTo(page, group);
            await page.keyboard.press("Space");
        }
        await tabTo(page, post);
        await Promise.all([
            page.waitForNavigation({ waitUntil: "networkidle2" }),
            page.keyboard.press("Enter"),
        ]);

        const stored = JSON.parse(execFileSync("perl", [
            path.join(__dirname, "fixtures", fixtureName + ".pl"), "--entry", fixture.user, subject,
        ], { encoding: "utf8" }));
        const expected = (1 << fixture.bits[0]) | (1 << fixture.bits[2]);
        assert.deepEqual(stored, { security: "usemask", mask: expected },
            "the journal saves exactly the two keyboard-selected groups");
        console.log("PASS: keyboard-selected custom security persists (JS=" + javaScript + ")");
    } finally {
        await page.close();
    }
}

(async () => {
    const fixture = createFixture(fixtureName);
    let browser;
    try {
        browser = await launch();
        const cookies = await login(browser, fixture.user, fixture.password);
        for (const javaScript of [true, false]) {
            try {
                await checkPosting(browser, cookies, fixture, javaScript);
            } catch (error) {
                console.error("FAIL: keyboard custom security (JS=" + javaScript + ")", error);
                process.exitCode = 1;
            }
        }
    } finally {
        if (browser) await browser.close();
        deleteFixture(fixtureName, fixture.user);
    }
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
