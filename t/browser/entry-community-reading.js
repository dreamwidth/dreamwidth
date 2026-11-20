// t/browser/entry-community-reading.js
//
// Check that the new entry form offers "Don't show on Reading pages" only when
// posting to a personal journal. Communities reject that option, so the form
// must hide it and leave it out of the submission. Uses the Chrome and
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
// Run inside the devcontainer (see t/browser/README.md):
//   node t/browser/entry-community-reading.js
// It creates its own account and community, and removes them afterwards. It
// changes only unsaved form state; it never submits the entry form.

"use strict";

const assert = require("node:assert/strict");
const { BASE, launch, createFixture, deleteFixture, login } = require("./lib/browser");

const OPTION = 'input[name="entrytime_outoforder"]';

// What the user sees and what the real form would send.
function optionState(page) {
    return page.$eval(OPTION, input => {
        const label = input.closest("label") || document.querySelector('label[for="' + input.id + '"]');
        return {
            visible: input.checkVisibility() && label.checkVisibility(),
            checked: input.checked,
            submitted: new FormData(input.form).get(input.name)
        };
    });
}

async function openForm(browser, cookies, path, javaScriptEnabled, width) {
    const page = await browser.newPage();
    await page.setViewport({ width, height: 1000 });
    await page.setJavaScriptEnabled(javaScriptEnabled);
    await page.setCookie(...cookies);
    const response = await page.goto(BASE + path, { waitUntil: "networkidle2", timeout: 30000 });
    assert.equal(response.status(), 200, path + " loads");
    return page;
}

// Switching journals in the "Post to" menu hides the option for the community
// and restores the user's choice for their own journal.
async function checkSwitching(browser, cookies, fixture, width) {
    const page = await openForm(browser, cookies, "/entry/new", true, width);
    try {
        const values = await page.$$eval("#js-usejournal option", options => options.map(o => o.value));
        assert.ok(values.includes("") && values.includes(fixture.community),
            "Post to menu lists the journal and the community");

        assert.deepEqual(await optionState(page), { visible: true, checked: false, submitted: null },
            "option is offered for the personal journal");
        await page.click(OPTION);
        assert.deepEqual(await optionState(page), { visible: true, checked: true, submitted: "1" });

        await page.select("#js-usejournal", fixture.community);
        const community = await optionState(page);
        assert.equal(community.visible, false, "option is hidden for the community");
        assert.equal(community.submitted, null, "option is not submitted for the community");

        await page.select("#js-usejournal", "");
        assert.deepEqual(await optionState(page), { visible: true, checked: true, submitted: "1" },
            "the personal journal keeps the user's choice");

        console.log("PASS: switching journals, width=" + width);
    } finally {
        await page.close();
    }
}

// A form opened for the community never offers the option, with or without
// page JavaScript.
async function checkCommunityForm(browser, cookies, fixture, javaScriptEnabled, width) {
    const page = await openForm(browser, cookies, "/entry/" + fixture.community + "/new",
        javaScriptEnabled, width);
    try {
        assert.equal(await page.$eval("#js-usejournal", input => input.value), fixture.community,
            "form posts to the community");
        const state = await optionState(page);
        assert.equal(state.visible, false, "option is hidden");
        assert.equal(state.submitted, null, "option is not submitted");
        console.log("PASS: community form, JS=" + javaScriptEnabled + ", width=" + width);
    } finally {
        await page.close();
    }
}

(async () => {
    const fixture = createFixture("entry-community");
    let browser;
    try {
        browser = await launch();
        const cookies = await login(browser, fixture.user, fixture.password);
        for (const width of [1280, 390]) {
            await checkSwitching(browser, cookies, fixture, width);
            for (const javaScriptEnabled of [true, false]) {
                await checkCommunityForm(browser, cookies, fixture, javaScriptEnabled, width);
            }
        }
    } finally {
        if (browser) await browser.close();
        deleteFixture("entry-community", fixture.community);
        deleteFixture("entry-community", fixture.user);
    }
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
