// t/browser/entry-slug-preview.js
//
// Check that the Entry Link preview follows the slug, date, and journal.
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

const SLUG = "#js-entry-slug";
const DATE = "#js-entrytime-date";
const JOURNAL = "#js-usejournal";
const PREVIEW = "#js-slug-base";

function value(page, selector) {
    return page.$eval(selector, input => input.value);
}

function preview(page) {
    return page.$eval(PREVIEW, element => element.textContent);
}

async function clear(page, selector) {
    await page.focus(selector);
    await page.keyboard.down("Control");
    await page.keyboard.press("A");
    await page.keyboard.up("Control");
    await page.keyboard.press("Backspace");
}

(async () => {
    const fixture = createFixture("entry-community");
    let browser;
    try {
        browser = await launch();
        const cookies = await login(browser, fixture.user, fixture.password);
        const page = await browser.newPage();
        await page.setCookie(...cookies);
        const response = await page.goto(BASE + "/entry/new", { waitUntil: "networkidle2", timeout: 30000 });
        assert.equal(response.status(), 200, "new entry form loads");

        const date = (await value(page, DATE)).replaceAll("-", "/");
        const personalBase = `${BASE}/~${fixture.user}/`;
        const communityBase = `${BASE}/~${fixture.community}/`;

        await page.type(SLUG, "My");
        assert.match(await preview(page), /\/my\.html$/, "the preview includes the slug while typing");
        await page.type(SLUG, "  FIRST -- Post_2!");
        assert.equal(await preview(page), `${personalBase}${date}/my-first-post_2.html`,
            "the preview shows the complete normalized personal journal URL");
        assert.equal(await value(page, SLUG), "My  FIRST -- Post_2!", "typing does not rewrite the field");

        await page.keyboard.press("Tab");
        assert.equal(await value(page, SLUG), "my-first-post_2", "leaving the field still normalizes it");
        await page.select(JOURNAL, fixture.community);
        assert.equal(await preview(page), `${communityBase}${date}/my-first-post_2.html`,
            "switching journals keeps the slug and uses the community URL");

        if (await page.$eval("#js-entrytime-autoupdate", input => input.checked)) {
            await page.click("#js-entrytime-autoupdate");
        }
        await clear(page, DATE);
        await page.type(DATE, "2024-05-29");
        await page.keyboard.press("Tab");
        assert.equal(await preview(page), `${communityBase}2024/05/29/my-first-post_2.html`,
            "committing a different date also updates the URL");

        await clear(page, SLUG);
        assert.equal(await preview(page), `${communityBase}2024/05/29/`, "clearing removes the slug and suffix");
        await page.type(SLUG, "!!!");
        assert.equal(await preview(page), `${communityBase}2024/05/29/`,
            "input that becomes empty never produces a bare .html suffix");

        console.log("PASS: Entry Link updates while typing and after changing the journal or date");
    } finally {
        if (browser) await browser.close();
        deleteFixture("entry-community", fixture.community);
        deleteFixture("entry-community", fixture.user);
    }
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
