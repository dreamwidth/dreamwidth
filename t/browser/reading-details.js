// t/browser/reading-details.js
//
// Check that the reading-page cut controls and preference open entry Details
// without changing disclosure controls outside entry content.
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
// Run inside the devcontainer (see t/browser/README.md):
//   node t/browser/reading-details.js

"use strict";

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const path = require("node:path");
const { BASE, launch, createFixture, deleteFixture, login } = require("./lib/browser");

const FIXTURE = "reading-details";
const ENTRY_DETAILS = ".entry-content details";
const OUTER_DETAILS = ".entry-content > details";
const AJAX_DETAILS = ".entry-content .cuttag-open details";
const EXPAND = '.cutTagControls a img[alt="Expand All Cut Tags"]';
const COLLAPSE = '.cutTagControls a img[alt="Collapse All Cut Tags"]';
const CLOSED = [["Field notes", false], ["One more observation", false]];
const OPEN = [["Field notes", true], ["One more observation", true], ["Detour notes", true]];

function setPreference(fixture, enabled) {
    execFileSync("perl", [path.join(__dirname, "fixtures", FIXTURE + ".pl"),
        "--preference", fixture.user, enabled ? "1" : "0"]);
}

function detailsState(page, selector = ENTRY_DETAILS) {
    return page.$$eval(selector, elements => elements.map(element => [
        element.querySelector("summary").textContent, element.open,
    ]));
}

async function openPage(browser, cookies, route, javaScriptEnabled) {
    const page = await browser.newPage();
    await page.setCookie(...cookies);
    await page.setJavaScriptEnabled(javaScriptEnabled);
    const response = await page.goto(BASE + route, { waitUntil: "networkidle2" });
    assert.equal(response.status(), 200, route + " loads");
    await page.waitForSelector(OUTER_DETAILS);
    return page;
}

async function checkControls(browser, cookies, route) {
    const page = await openPage(browser, cookies, route, true);
    try {
        assert.deepEqual(await detailsState(page), CLOSED);
        await page.evaluate(() => {
            const nav = document.createElement("nav");
            nav.id = "fixture-nav";
            nav.innerHTML = '<details id="nav-open" open><summary>Menu</summary></details>' +
                '<details id="nav-closed"><summary>Other menu</summary></details>';
            document.body.append(nav);
        });
        const unchanged = [["Menu", true], ["Other menu", false]];
        await page.click(EXPAND);
        await page.waitForSelector(AJAX_DETAILS);
        assert.deepEqual(await detailsState(page), OPEN,
            "expand all opens entry Details, including nested and AJAX-loaded Details");
        assert.deepEqual(await detailsState(page, "#fixture-nav details"), unchanged);

        await page.click(COLLAPSE);
        assert.deepEqual(await detailsState(page), CLOSED,
            "collapse all closes the Details and removes the expanded cut");
        assert.deepEqual(await detailsState(page, "#fixture-nav details"), unchanged);

        await page.click(OUTER_DETAILS + " > summary");
        assert.equal(await page.$eval(OUTER_DETAILS, details => details.open), true,
            "clicking a summary still opens the Details natively");
        await page.click(".cuttag-action-before");
        await page.waitForSelector(AJAX_DETAILS);
        assert.equal(await page.$eval(AJAX_DETAILS, details => details.open), false,
            "expanding a single cut does not force its Details open");
    } finally {
        await page.close();
    }
}

async function checkPreference(browser, cookies, route) {
    const page = await openPage(browser, cookies, route, false);
    try {
        assert.deepEqual(await detailsState(page), OPEN,
            "the reading preference expands every entry Details without JavaScript");
        assert.equal(await page.$(".entry-content .cuttag"), null, "cuts are already expanded");
    } finally {
        await page.close();
    }
}

async function checkDetailsOnly(browser, cookies, route) {
    const page = await openPage(browser, cookies, route, true);
    try {
        assert.ok(await page.$(COLLAPSE), "Details alone enable collapse all");
        await page.click(COLLAPSE);
        await page.waitForSelector(EXPAND);
        assert.ok((await detailsState(page)).every(([, open]) => !open),
            "collapse all works when the page has Details and no collapsible cut tags");
        await page.click(EXPAND);
        assert.ok((await detailsState(page)).every(([, open]) => open),
            "expand all works when the page has Details and no collapsible cut tags");
        await page.click(OUTER_DETAILS + " > summary");
        await page.waitForSelector(EXPAND);
    } finally {
        await page.close();
    }
}

async function run() {
    const fixture = createFixture(FIXTURE);
    let browser;
    try {
        browser = await launch();
        const cookies = await login(browser, fixture.user, fixture.password);
        const route = "/~" + fixture.user + "/read";
        const cases = [
            ["cut controls", () => checkControls(browser, cookies, route)],
            ["reading preference", async () => {
                setPreference(fixture, true);
                await checkPreference(browser, cookies, route);
            }],
            ["Details-only controls", () => checkDetailsOnly(browser, cookies, route)],
            ["journal preference is separate", async () => {
                const page = await openPage(browser, cookies, "/~" + fixture.poster + "/", false);
                try {
                    assert.deepEqual(await detailsState(page), CLOSED);
                } finally {
                    await page.close();
                }
            }],
        ];
        for (const [name, check] of cases) {
            try {
                await check();
                console.log("PASS: " + name);
            } catch (error) {
                console.error("FAIL: " + name, error);
                process.exitCode = 1;
            }
        }
    } finally {
        if (browser) await browser.close();
        deleteFixture(FIXTURE, fixture.user);
        deleteFixture(FIXTURE, fixture.poster);
    }
}

run().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
