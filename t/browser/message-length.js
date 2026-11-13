// t/browser/message-length.js
//
// Check live private-message limits and the no-JavaScript server fallback on
// both supported composers. No message is sent by this test.
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
// Run inside the devcontainer: node t/browser/message-length.js

"use strict";

const assert = require("node:assert/strict");
const { BASE, launch, createFixture, deleteFixture, login } = require("./lib/browser");

async function setBody(page, value) {
    await page.$eval('textarea[name="msg_body"]', (body, text) => {
        body.value = text;
        body.dispatchEvent(new Event("input", { bubbles: true }));
    }, value);
}

async function state(page) {
    return page.$eval('textarea[name="msg_body"]', body => ({
        value: body.value,
        valid: body.validity.valid,
        warning: document.getElementById("msg_body_warning").textContent,
    }));
}

async function checkComposer(browser, cookies, fixture, route) {
    const page = await browser.newPage();
    try {
        await page.setCookie(...cookies);
        const response = await page.goto(BASE + route, { waitUntil: "networkidle2" });
        assert.equal(response.status(), 200);
        assert.ok(fixture.limit > 4, "fixture has a usable account limit");
        const semantics = await page.$eval('textarea[name="msg_body"]', body => ({
            labelled: Array.from(body.labels).some(label => label.textContent.trim()),
            described: body.getAttribute("aria-describedby").split(/\s+/)
                .every(id => document.getElementById(id)),
            live: document.getElementById("msg_body_warning").getAttribute("aria-live"),
            limit: Number(body.dataset.messageLimit),
        }));
        assert.deepEqual(semantics, {
            labelled: true, described: true, live: "polite", limit: fixture.limit,
        });

        // Expected lengths are explicit, independent of the product counter.
        const cases = [
            ["below", "a".repeat(fixture.limit - 1), true],
            ["exact", "a".repeat(fixture.limit), true],
            ["above", "a".repeat(fixture.limit + 1), false],
            ["BMP exact", "é".repeat(fixture.limit), true],
            ["supplementary exact", "😀".repeat(fixture.limit), true],
            ["supplementary above", "😀".repeat(fixture.limit + 1), false],
            ["combining exact", "a".repeat(fixture.limit - 2) + "e\u0301", true],
            ["combining above", "a".repeat(fixture.limit - 1) + "e\u0301", false],
            ["newline exact", "a".repeat(fixture.limit - 2) + "\n", true],
            ["newline above", "a".repeat(fixture.limit - 1) + "\n", false],
        ];
        for (const [name, text, valid] of cases) {
            await setBody(page, text);
            const result = await state(page);
            assert.equal(result.value, text, name + ": text is retained");
            assert.equal(result.valid, valid, name + ": browser validity");
            assert.equal(Boolean(result.warning), !valid, name + ": visible warning");
        }

        // A real keystroke crosses the limit, then Backspace permits sending.
        await setBody(page, "a".repeat(fixture.limit));
        await page.focus('textarea[name="msg_body"]');
        await page.keyboard.press("End");
        await page.keyboard.type("x");
        assert.equal((await state(page)).valid, false);

        let posts = 0;
        page.on("request", request => { if (request.method() === "POST") posts++; });
        await page.$eval('textarea[name="msg_body"]', body => {
            body.addEventListener("invalid", () => { window.lengthRejected = true; });
        });
        await page.click('#compose input[type="submit"]');
        await page.waitForFunction(() => window.lengthRejected === true);
        assert.equal(posts, 0, "overlong message is stopped before POST");
        assert.equal((await state(page)).value.length, fixture.limit + 1);

        await page.focus('textarea[name="msg_body"]');
        await page.keyboard.press("End");
        await page.keyboard.press("Backspace");
        assert.equal((await state(page)).valid, true, "editing below limit clears validity");
        assert.equal((await state(page)).warning, "", "editing below limit clears warning");

        // With JavaScript off, the existing server validation must still reject
        // a too-long body and return all the text, rather than sending it.
        await page.setJavaScriptEnabled(false);
        await page.goto(BASE + route, { waitUntil: "networkidle2" });
        const overlong = "a".repeat(fixture.limit - 1) + "\n";
        await setBody(page, overlong);
        await page.$eval('input[name="msg_to"]', (input, user) => { input.value = user; }, fixture.user);
        await Promise.all([
            page.waitForNavigation({ waitUntil: "networkidle2" }),
            page.click('#compose input[type="submit"]'),
        ]);
        const retained = await page.$eval('textarea[name="msg_body"]', body => body.value);
        assert.equal(retained, overlong, "server retains rejected multiline text");
        const text = await page.$eval("body", body => body.textContent);
        assert.match(text, /Message body is too long/, "server rejects the submitted CRLF length");
        console.log("PASS: private-message length " + route);
    } finally {
        await page.close();
    }
}

(async () => {
    const fixture = createFixture("message-length");
    let browser;
    try {
        browser = await launch();
        const cookies = await login(browser, fixture.user, fixture.password);
        for (const route of ["/inbox/new/compose", "/inbox/compose"]) {
            await checkComposer(browser, cookies, fixture, route);
        }
    } finally {
        if (browser) await browser.close();
        deleteFixture("message-length", fixture.user);
    }
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
