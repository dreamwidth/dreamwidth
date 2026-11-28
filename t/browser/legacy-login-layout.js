// t/browser/legacy-login-layout.js
//
// Check the space for the logged-out login form in legacy site schemes.
//
// Authors:
//      Alex <saphid@users.noreply.github.com>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself. For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

"use strict";

const assert = require("node:assert/strict");
const { BASE, launch } = require("./lib/browser");

const schemes = {
    "tropo-red": ["tropo tropo-red", '#page > nav[role="navigation"]'],
    "tropo-purple": ["tropo tropo-purple", '#page > nav[role="navigation"]'],
    celerity: ["celerity", "#header-divider"],
    "celerity-local": ["celerity", "#header-divider"],
    "gradation-horizontal": ["gradation", "#header-search"],
    "gradation-horizontal-local": ["gradation", "#header-search"],
    "gradation-vertical": ["gradation", "#header-search"],
    "gradation-vertical-local": ["gradation", "#header-search"],
    blueshift: ["gradation", "#header-search"],
};
const scenarios = [
    ["default", 0, 1],
    ["larger inputs", 23, 1],
    ["zoomed", 0, 1.5],
    ["larger inputs and zoomed", 32, 1.5],
];

async function checkTropoDropdown(page) {
    const nav = '#page > nav[role="navigation"]';
    await page.mouse.move(0, 0);
    await page.hover(`${nav} .topnav:has(.subnav + .subnav) > a`);
    const submenu = `${nav} .topnav.hover .subnav > a`;
    await page.waitForSelector(submenu, { visible: true });
    const reachable = await page.$$eval(submenu, links => {
        const content = document.querySelector("#content");
        const bounds = content.getBoundingClientRect();
        for (const link of links) {
            const rect = link.getBoundingClientRect();
            const x = rect.left + rect.width / 2;
            const y = rect.top + rect.height / 2;
            if (!(x > bounds.left && x < bounds.right && y > bounds.top && y < bounds.bottom)) continue;

            const overlay = document.createElement("div");
            overlay.style.cssText = `position: fixed; z-index: 5; left: ${x - 4}px;
                top: ${y - 4}px; width: 8px; height: 8px;`;
            content.append(overlay);
            const stack = document.elementsFromPoint(x, y);
            overlay.remove();
            return link.contains(stack[0]) && stack.includes(overlay);
        }
        return false;
    });
    assert.ok(reachable, "open dropdown is above positioned page content");
}

(async () => {
    const browser = await launch();
    const failures = [];
    try {
        const page = await browser.newPage();
        for (const [scheme, [bodyClass, nextBar]] of Object.entries(schemes)) {
            const response = await page.goto(`${BASE}/update?skin=${scheme}`, { waitUntil: "load" });
            assert.equal(response.status(), 200, scheme);
            assert.equal(await page.$eval("body", body => body.className), bodyClass, scheme);
            if (scheme.startsWith("gradation")) {
                assert.equal(await page.$eval("#canvas", canvas => canvas.className),
                    `${scheme.split("-")[1]}-nav`, scheme);
            }
            if (scheme.endsWith("-local")) {
                const skin = scheme.split("-")[0];
                const image = `#masthead #logo img[src$="/${skin}/dw_logo_${skin}.png"]`;
                assert.ok(await page.$eval(image, img => img.naturalWidth > 0),
                    `${scheme} uses the Dreamwidth image logo`);
            }
            if (scheme === "blueshift") {
                assert.ok(await page.$('link[href*="blueshift.css"]'), "Blueshift stylesheet");
            }
            if (scheme.startsWith("tropo")) {
                await checkTropoDropdown(page);
                console.log(`PASS: ${scheme}: dropdown stacking`);
            }
            for (const [scenario, fontSize, zoom] of scenarios) {
                const layout = await page.evaluate((bar, fontSize, zoom) => {
                    document.documentElement.style.zoom = zoom;
                    const masthead = document.querySelector("#masthead");
                    const account = masthead.querySelector("#account-links");
                    const table = account.querySelector("#login-table");
                    const fields = [...table.querySelectorAll("#login_user, #login_password")];
                    for (const field of fields) field.style.fontSize = fontSize ? `${fontSize}px` : "";
                    const tableBox = table.getBoundingClientRect();
                    const accountBox = account.getBoundingClientRect();
                    const logo = masthead.querySelector("#logo a").getBoundingClientRect();
                    const logoBox = (masthead.querySelector("#logo img")
                        || masthead.querySelector("#logo a")).getBoundingClientRect();
                    const mastheadBox = masthead.getBoundingClientRect();
                    const next = document.querySelector(bar).getBoundingClientRect();
                    return {
                        fieldCount: fields.length,
                        bottomGap: Math.min(accountBox.bottom, mastheadBox.bottom, next.top) - tableBox.bottom,
                        logoVisible: logo.width > 0 && logo.height > 0,
                        overlapsLogo: tableBox.left < logoBox.right && tableBox.right > logoBox.left
                            && tableBox.top < logoBox.bottom && tableBox.bottom > logoBox.top,
                        logoRightAligned: Math.abs(mastheadBox.right - logoBox.right
                            - parseFloat(getComputedStyle(masthead).paddingRight) * zoom) <= 2,
                        logoBelowTop: logoBox.top - mastheadBox.top > 30 * zoom,
                        usable: [...table.querySelectorAll("input, a")].every(control => {
                            const rect = control.getBoundingClientRect();
                            return rect.width > 0 && rect.height > 0
                                && document.elementFromPoint(rect.x + rect.width / 2,
                                    rect.y + rect.height / 2) === control;
                        }),
                    };
                }, nextBar, fontSize, zoom);
                const label = `${scheme}: ${scenario}`;
                try {
                    assert.equal(layout.fieldCount, 2);
                    assert.ok(layout.bottomGap >= -1, `login table overflows by ${-layout.bottomGap}px`);
                    assert.ok(layout.logoVisible, "logo link has a visible box");
                    assert.ok(!layout.overlapsLogo, "login form overlaps the logo");
                    if (scheme.startsWith("celerity")) {
                        assert.ok(layout.logoRightAligned && layout.logoBelowTop,
                            "Celerity logo retains its right alignment and top inset");
                    }
                    assert.ok(layout.usable, "login controls and links are reachable");
                    console.log(`PASS: ${label}`);
                } catch (error) {
                    failures.push(`${label}: ${error.message}`);
                }
            }
        }
        assert.deepEqual(failures, []);
    } finally {
        await browser.close();
    }
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
