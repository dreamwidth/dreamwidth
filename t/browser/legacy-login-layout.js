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
    "gradation-horizontal": ["gradation", "#header-search"],
    "gradation-vertical": ["gradation", "#header-search"],
    blueshift: ["gradation", "#header-search"],
};
const scenarios = [
    ["default", 0, 1],
    ["larger inputs", 23, 1],
    ["zoomed", 0, 1.5],
    ["larger inputs and zoomed", 32, 1.5],
];

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
            if (scheme === "blueshift") {
                assert.ok(await page.$('link[href*="blueshift.css"]'), "Blueshift stylesheet");
            }
            for (const [scenario, fontSize, zoom] of scenarios) {
                const layout = await page.evaluate((bar, fontSize, zoom) => {
                    document.documentElement.style.zoom = zoom;
                    const account = document.querySelector("#account-links");
                    const table = account.querySelector("#login-table");
                    const fields = [...table.querySelectorAll("#login_user, #login_password")];
                    for (const field of fields) field.style.fontSize = fontSize ? `${fontSize}px` : "";
                    const tableBox = table.getBoundingClientRect();
                    const accountBox = account.getBoundingClientRect();
                    const logo = document.querySelector("#masthead a").getBoundingClientRect();
                    const next = document.querySelector(bar).getBoundingClientRect();
                    return {
                        fieldCount: fields.length,
                        bottomGap: Math.min(accountBox.bottom, next.top) - tableBox.bottom,
                        overlapsLogo: tableBox.left < logo.right && tableBox.right > logo.left
                            && tableBox.top < logo.bottom && tableBox.bottom > logo.top,
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
                    assert.ok(!layout.overlapsLogo, "login form overlaps the logo");
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
