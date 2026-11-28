// t/browser/customize-community.js
//
// Community customization must not fall back to the maintainer's journal.
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

const fixtureName = "customize-community";
const themeName = "Community Custom Theme";
const currentTheme = ".theme-current h3";

function state(user) {
    return JSON.parse(execFileSync("perl", [
        path.join(__dirname, "fixtures", `${fixtureName}.pl`), "--state", user,
    ], { encoding: "utf8" }));
}

async function navigate(page, selector) {
    await Promise.all([page.waitForNavigation({ waitUntil: "domcontentloaded" }), page.click(selector)]);
}

async function exercise(page, fixture, cookies) {
    await page.goto(`${BASE}/customize/`, { waitUntil: "load" });
    await page.waitForSelector(currentTheme);
    const personalBefore = state(fixture.user);
    const switcher = '.theme-switcher select[name="authas"]';
    await page.select(switcher, fixture.community);
    await navigate(page, '.theme-switcher input[type="submit"]');

    const filter = '.theme-selector-nav a[href*="cat=custom"]';
    await page.click(filter);
    const apply = `input.theme_button[data-themeid="${fixture.theme}"]`;
    await page.waitForSelector(apply, { visible: true });

    const preview = await page.$eval(apply, input => input.closest(".theme-item").querySelector(".theme-preview-link").href);
    const cookieHeader = cookies.map(({ name, value }) => `${name}=${value}`).join("; ");
    const previewResponse = await fetch(preview, { headers: { cookie: cookieHeader }, redirect: "manual" });
    const previewLocation = previewResponse.headers.get("location") || "";

    let applied = false;
    page.on("dialog", async dialog => {
        applied = true;
        await dialog.accept();
    });
    await page.click(apply);
    await page.waitForFunction((selector, theme) => document.querySelector(selector)?.textContent.trim() === theme,
        {}, currentTheme, themeName);
    assert.ok(applied, "the AJAX apply flow completes");
    assert.equal(state(fixture.community).theme, fixture.theme, "apply saves the community theme");
    assert.deepEqual(state(fixture.user), personalBefore, "apply leaves the maintainer's style untouched");

    const options = '.theme-current-links a[href*="/customize/options"]';
    await navigate(page, options);
    assert.equal(new URL(page.url()).searchParams.get("authas"), fixture.community);
    assert.equal(await page.$eval(currentTheme, heading => heading.textContent.trim()), themeName,
        "the applied theme persists on the community's options page");

    await page.click("#journaltitle_edit");
    await page.$eval("#journaltitle", input => { input.value = ""; });
    await page.type("#journaltitle", "Updated Community Journal");
    await page.click('#journaltitle_form input[type="submit"]');
    await page.waitForFunction(() => document.querySelector("#journaltitle_view strong")?.textContent.includes("Updated Community Journal"));
    assert.equal(state(fixture.community).title, "Updated Community Journal", "options saves the community title");
    assert.deepEqual(state(fixture.user), personalBefore, "options leaves the maintainer's title and styles unchanged");

    const edit = '.theme-current-links a[href*="/advanced/layeredit"]';
    const editLink = await page.$eval(edit, anchor => anchor.href);
    const optionsUrl = page.url();
    const advanced = '.theme-current-links a[href*="/customize/advanced/"]:not([href*="layeredit"])';
    const advancedFooter = await page.$eval('h2.widget-header + a', anchor => new URL(anchor.href).searchParams.get("authas"));
    assert.equal(advancedFooter, fixture.community, "the options page's Advanced link keeps the community");
    await navigate(page, advanced);
    await navigate(page, 'a[href*="/customize/advanced/layers"]');
    const layerPage = new URL(page.url());
    const layerId = `#table_yourlayers a[href="layerbrowse?id=${fixture.theme}"]`;
    const communityLayer = await page.$(layerId);

    const failures = [];
    if (layerPage.searchParams.get("authas") !== fixture.community || !communityLayer) {
        failures.push("Advanced customization opened the maintainer's layer list instead of the community's");
    } else {
        await navigate(page, layerId);
        assert.match(await page.title(), /Community Custom Theme/, "the layer ID opens the community theme details");
        await navigate(page, 'a[href*="/customize/advanced/layers"]');
        if (new URL(page.url()).searchParams.get("authas") !== fixture.community || !await page.$(layerId)) {
            failures.push("The layer details Your Layers backlink did not return to the community's layer list");
        }
    }
    if (![301, 302, 303, 307, 308].includes(previewResponse.status) || !previewLocation.includes(fixture.community)) {
        failures.push("preview did not redirect to the community journal");
    }
    if (new URL(editLink).searchParams.get("id") !== String(fixture.theme)) {
        failures.push("Edit Theme Layer did not link to the applied layer");
    } else {
        await page.goto(optionsUrl, { waitUntil: "domcontentloaded" });
        await navigate(page, edit);
        assert.match(await page.title(), /Community Custom Theme/, "the editor opens the applied theme");
    }
    return failures;
}

async function checkDenied(browser, fixture, failures) {
    const context = await browser.createBrowserContext();
    try {
        await login(context, fixture.outsider, fixture.password);
        const page = await context.newPage();
        for (const route of ["", "layers", "styles"]) {
            const pathname = `/customize/advanced/${route}`;
            await page.goto(`${BASE}${pathname}?authas=${fixture.community}`, { waitUntil: "domcontentloaded" });
            const body = await page.$eval("body", element => element.textContent);
            if (!/couldn't be authenticated as the specified account/.test(body)) {
                failures.push(`${pathname} did not reject a non-maintainer selecting the community`);
            }
        }
    } finally {
        await context.close();
    }
}

(async () => {
    const fixture = createFixture(fixtureName);
    let browser;
    try {
        browser = await launch();
        const cookies = await login(browser, fixture.user, fixture.password);
        const page = await browser.newPage();
        await page.setCookie(...cookies);
        const failures = await exercise(page, fixture, cookies);
        await checkDenied(browser, fixture, failures);
        assert.deepEqual(failures, []);
        console.log("PASS: community preview, theme apply, settings save, layer navigation, and authorization");
    } finally {
        try {
            if (browser) await browser.close();
        } finally {
            try {
                deleteFixture(fixtureName, fixture.community);
            } finally {
                try {
                    deleteFixture(fixtureName, fixture.user);
                } finally {
                    deleteFixture(fixtureName, fixture.outsider);
                }
            }
        }
    }
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
