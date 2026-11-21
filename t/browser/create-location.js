// t/browser/create-location.js
// Check location selection during account setup with and without JavaScript.
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

const setup = BASE + "/create/setup";
const country = 'select[name="country"]';
const stateText = 'input[name="stateother"]';
const stateSelect = 'select[name="statedrop"]';

async function submit(page) {
    await Promise.all([
        page.waitForNavigation({ waitUntil: "domcontentloaded" }),
        page.click('form[action*="/create/setup"] input[type="submit"]'),
    ]);
}

function assertContinued(page, message) {
    assert.match(new URL(page.url()).pathname, /^\/create\/(?:next|upgrade)$/, message);
}

async function enterState(page, text) {
    await page.waitForSelector(stateText, { visible: true });
    await page.click(stateText, { clickCount: 3 });
    await page.type(stateText, text);
}

function value(page, selector) {
    return page.$eval(selector, field => field.value);
}

async function checkDelayedStateList(page) {
    const isStateRequest = request => request.method() === "POST"
        && new URL(request.url()).pathname.endsWith("/__rpc_load_state_codes");
    const intercept = request => {
        if (!isStateRequest(request)) return request.continue();
    };
    await page.setRequestInterception(true);
    page.on("request", intercept);
    const [request] = await Promise.all([
        page.waitForRequest(isStateRequest),
        page.select(country, "US"),
    ]);
    assert.equal(new URLSearchParams(request.postData()).get("country"), "US");
    await page.select(country, "CA");
    await enterState(page, "Ontario");
    await page.evaluate(() => {
        window.stateRequestSettled = new Promise(resolve => {
            jQuery(document).one("ajaxStop", () => setTimeout(resolve, 0));
        });
    });
    const [response] = await Promise.all([
        page.waitForResponse(response => response.request() === request),
        request.continue(),
    ]);
    assert.equal(response.status(), 200);
    await page.evaluate(() => window.stateRequestSettled);
    page.off("request", intercept);
    await page.setRequestInterception(false);

    assert.equal(await page.$eval(stateText, field => !field.disabled && field.getClientRects().length > 0),
        true, "a late US response must not replace the Canadian text field");
    assert.equal(await value(page, stateText), "Ontario");
    await submit(page);
    assertContinued(page, "Canadian free text still submits after the delayed response");
    await page.goto(setup);
    assert.equal(await value(page, country), "CA");
    assert.equal(await value(page, stateText), "Ontario");
    console.log("PASS: a delayed US response cannot discard a Canadian province");
}

(async () => {
    const fixture = createFixture("create-location");
    let browser;
    try {
        browser = await launch();
        const cookies = await login(browser, fixture.user, fixture.password);
        const page = await browser.newPage();
        await page.setCookie(...cookies);
        await page.setJavaScriptEnabled(false);
        assert.equal((await page.goto(setup)).status(), 200);
        await page.select(country, "US");
        await enterState(page, "California");
        await submit(page);
        assertContinued(page, "entering a US state without JavaScript advances account setup");
        await page.goto(setup);
        assert.equal(await value(page, stateText), "CA", "the canonical US state code is saved");
        console.log("PASS: account setup accepts and saves a US state without JavaScript");

        await enterState(page, "Atlantis");
        await submit(page);
        assert.equal(new URL(page.url()).pathname, "/create/setup");
        assert.match(await page.$eval("body", body => body.innerText), /valid state, region, or territory/);
        assert.equal(await value(page, stateText), "Atlantis", "rejected text remains editable");
        await enterState(page, " ny ");
        await submit(page);
        assertContinued(page, "a trimmed, lowercase state code can correct an invalid state");
        await page.goto(setup);
        assert.equal(await value(page, stateText), "NY");
        console.log("PASS: invalid states are rejected and a corrected code is saved");

        await page.select(country, "CA");
        await enterState(page, "Ontario");
        await submit(page);
        assertContinued(page, "changing from a US state to free-text Canadian province works");
        await page.goto(setup);
        assert.equal(await value(page, country), "CA");
        assert.equal(await value(page, stateText), "Ontario");
        console.log("PASS: changing from a configured country to free-text regions works without JavaScript");

        await page.setJavaScriptEnabled(true);
        await page.goto(setup);
        await checkDelayedStateList(page);

        await page.select(country, "US");
        await page.waitForSelector(stateSelect, { visible: true });
        assert.deepEqual(await page.select(stateSelect, "WA"), ["WA"]);
        await submit(page);
        assertContinued(page, "selecting a state from the JavaScript dropdown advances account setup");
        await page.goto(setup);
        await page.waitForSelector(stateSelect, { visible: true });
        assert.equal(await value(page, stateSelect), "WA", "the saved state is preselected");
        console.log("PASS: JavaScript loads the dropdown and saves and restores the selected state");

        await page.setJavaScriptEnabled(false);
        await page.goto(setup);
        await page.select(country, "CA");
        await enterState(page, "Ontario");
        await page.$eval(stateSelect, field => {
            field.disabled = false;
            field.value = "WA";
        });
        assert.equal(await value(page, stateSelect), "WA");
        await submit(page);
        assert.equal(new URL(page.url()).pathname, "/create/setup",
            "a dropdown value for a free-text country must not advance account setup");
        assert.match(await page.$eval("body", body => body.innerText), /valid state, region, or territory/);
        assert.equal(await value(page, stateText), "Ontario", "the entered province remains editable");
        await page.goto(setup);
        assert.equal(await value(page, country), "US");
        assert.equal(await value(page, stateText), "WA", "the rejected request does not change the saved state");
        console.log("PASS: a dropdown value for a free-text country is rejected without saving");

        await page.select(country, "RU");
        await enterState(page, "Адыгея Республика");
        await submit(page);
        assertContinued(page, "a non-ASCII region name works without JavaScript");
        await page.goto(setup);
        assert.equal(await value(page, stateText), "02");
        console.log("PASS: non-ASCII region names resolve to canonical codes");
    } finally {
        try {
            await browser?.close();
        } finally {
            deleteFixture("create-location", fixture.user);
        }
    }
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
