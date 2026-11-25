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
const journal = "#js-usejournal";
const optionsURL = "/__rpc_getsecurityoptions";

function isOptionsFor(url, user) {
    const parsed = new URL(url);
    return parsed.pathname === optionsURL && parsed.searchParams.get("user") === user;
}

function storedSecurity(user, subject) {
    return JSON.parse(execFileSync("perl", [
        path.join(__dirname, "fixtures", fixtureName + ".pl"), "--entry", user, subject,
    ], { encoding: "utf8" }));
}

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

        const stored = storedSecurity(fixture.user, subject);
        const expected = (1 << fixture.bits[0]) | (1 << fixture.bits[2]);
        assert.deepEqual(stored, { security: "usemask", mask: expected },
            "the journal saves exactly the two keyboard-selected groups");
        console.log("PASS: keyboard-selected custom security persists (JS=" + javaScript + ")");
    } finally {
        await page.close();
    }
}

async function checkJournalSwitching(browser, cookies, fixture) {
    const page = await browser.newPage();
    const first = `#custom-bit-${fixture.bits[0]}`;
    const groupState = () => page.$eval(first, input => ({
        hidden: input.closest("fieldset").hidden,
        disabled: input.matches(":disabled"),
    }));
    const waitForOption = value => page.waitForSelector(`${security} option[value="${value}"]`);
    const waitForCommunity = () => page.waitForFunction(selector => !document.querySelector(selector), {},
        `${security} option[value="custom"]`);
    let delayed;
    let holdCommunity = true;
    try {
        await page.setCookie(...cookies);
        await page.setRequestInterception(true);
        page.on("request", request => {
            if (holdCommunity && isOptionsFor(request.url(), fixture.community)) {
                delayed = request;
                return;
            }
            return request.continue();
        });
        await page.goto(BASE + "/entry/new", { waitUntil: "networkidle2" });
        await waitForOption("custom");
        await page.select(security, "custom");
        await page.click(first);
        assert.deepEqual(await groupState(), { hidden: false, disabled: false });

        await page.select(journal, fixture.community);
        assert.deepEqual(await groupState(), { hidden: true, disabled: true },
            "personal controls are unavailable before any community reply");
        await page.select(journal, "");
        await page.waitForNetworkIdle({ concurrency: 1 });
        assert.ok(delayed, "the community options request is still pending");
        holdCommunity = false;
        await delayed.continue();
        await page.waitForNetworkIdle();
        assert.ok(await page.$(`${security} option[value="custom"]`),
            "a late community reply cannot remove Personal's Custom option");
        await page.select(security, "custom");
        assert.deepEqual(await groupState(), { hidden: false, disabled: false },
            "returning to the personal journal makes its groups available");

        await page.select(journal, fixture.community);
        await waitForCommunity();
        assert.equal(await page.$eval(security, select => select.value), "access",
            "the community retains a restricted audience instead of a missing selection");
        assert.deepEqual(await groupState(), { hidden: true, disabled: true });
        assert.equal(await page.$eval(first, input => new FormData(input.form).has("custom_bit")),
            false, "the community submission omits the personal filters");

        await page.select(journal, "");
        await waitForOption("custom");
        await page.select(security, "custom");
        assert.deepEqual(await groupState(), { hidden: false, disabled: false },
            "the personal groups can be selected again after the community response");

        const subject = "Community before audience options arrive";
        await page.type('[name="subject"]', subject);
        await page.type('[name="event"]', "Synthetic community entry");
        holdCommunity = true;
        await Promise.all([
            page.waitForRequest(request => isOptionsFor(request.url(), fixture.community)),
            page.select(journal, fixture.community),
        ]);
        const [, submission] = await Promise.all([
            page.waitForNavigation({ waitUntil: "domcontentloaded" }),
            page.waitForRequest(request => request.method() === "POST" &&
                new URL(request.url()).pathname === "/entry/new"),
            page.click(post),
        ]);
        assert.doesNotMatch(await page.$eval("body", body => body.innerText),
            /Choose at least one access group/i, "posting before the reply does not require personal groups");
        assert.equal(new URLSearchParams(submission.postData()).get("security"), "access",
            "the pending community submission sends the members-only audience");
        assert.deepEqual(storedSecurity(fixture.community, subject), { security: "usemask", mask: 1 },
            "the community saves with members-only security before the reply");
        console.log("PASS: journal switching hides personal groups and preserves valid security");
    } finally {
        await page.close();
    }
}

async function checkPrivateMinimum(browser, cookies, fixture) {
    const page = await browser.newPage();
    const enabledAudiences = () => page.$eval(security, select => ({
        selected: select.value,
        label: select.selectedOptions[0].text,
        enabled: Array.from(select.options).filter(option => !option.disabled).map(option => option.value),
    }));
    const expected = { selected: "private", label: "administrators only", enabled: ["private"] };
    try {
        await page.setCookie(...cookies);
        await page.goto(BASE + "/entry/new", { waitUntil: "networkidle2" });
        const [response] = await Promise.all([
            page.waitForResponse(response => isOptionsFor(response.url(), fixture.restricted)),
            page.select(journal, fixture.restricted),
        ]);
        const { ret } = await response.json();
        assert.equal(ret.can_manage, 0, "the poster is not a community administrator");
        assert.equal(ret.minsecurity, "private", "the RPC returns the configured minimum");
        await page.waitForNetworkIdle();
        assert.deepEqual(await enabledAudiences(), expected,
            "only the enforced administrators-only audience is selectable");

        const subject = "Community with an administrators-only minimum";
        await page.type('[name="subject"]', subject);
        await page.type('[name="event"]', "Synthetic administrators-only community entry");
        await Promise.all([
            page.waitForNavigation({ waitUntil: "domcontentloaded" }),
            page.click(post),
        ]);
        assert.deepEqual(storedSecurity(fixture.restricted, subject), { security: "private", mask: 0 },
            "the non-admin's entry saves with the audience shown by the form");
        console.log("PASS: non-admin posting honors the community's administrators-only minimum");

        await page.setJavaScriptEnabled(false);
        await page.goto(BASE + "/entry/" + fixture.restricted + "/new", { waitUntil: "domcontentloaded" });
        assert.deepEqual(await enabledAudiences(), expected,
            "a preselected community offers the same enforced audience without JavaScript");
        console.log("PASS: server-rendered entry form honors the administrators-only minimum");
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
        await checkJournalSwitching(browser, cookies, fixture);
        await checkPrivateMinimum(browser, cookies, fixture);
    } finally {
        if (browser) await browser.close();
        deleteFixture(fixtureName, fixture.restricted);
        deleteFixture(fixtureName, fixture.community);
        deleteFixture(fixtureName, fixture.user);
        deleteFixture(fixtureName, fixture.admin);
    }
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
