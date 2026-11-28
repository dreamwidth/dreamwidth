// t/browser/leftovers-calendar.js
//
// Check that a rendered Leftovers calendar fits both sidebar positions.
//
// Authors:
//      SAPHID <saphid@users.noreply.github.com>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself.  For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

"use strict";

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const path = require("node:path");
const { BASE, launch, deleteFixture } = require("./lib/browser");

const cases = [
    { theme: "fruitsalad", section: "one", sidebar: "secondary", color: "rgb(255, 255, 255)" },
    { theme: "elegantbrown", section: "two", sidebar: "tertiary", color: "rgb(101, 86, 67)" },
];

async function runCalendarCases(width, sizes, check) {
    const browser = await launch();
    try {
        for (const { theme, section, sidebar, color } of cases) {
            const fixture = JSON.parse(execFileSync("perl", [
                path.join(__dirname, "fixtures", "leftovers-calendar.pl"), theme, section, String(width),
            ], { encoding: "utf8" }));
            let page;
            try {
                page = await browser.newPage();
                const response = await page.goto(BASE + fixture.path, { waitUntil: "networkidle2" });
                assert.equal(response.status(), 200);
                const selector = `#${sidebar} .module-calendar`;
                await page.waitForSelector(`${selector} table td a`);
                assert.equal(await page.$eval(selector, node => getComputedStyle(node).backgroundColor), color);

                for (const size of sizes) {
                    const style = await page.addStyleTag({ content: `.module-content { font-size: ${size}px; }` });
                    const geometry = await page.$eval(selector, module => {
                        const table = module.querySelector("table");
                        const box = module.getBoundingClientRect().toJSON();
                        const tableBox = table.getBoundingClientRect().toJSON();
                        const cell = table.querySelector("td a");
                        return {
                            box, tableBox,
                            days: table.querySelectorAll("th").length,
                            fontSize: getComputedStyle(cell).fontSize,
                        };
                    });
                    assert.equal(geometry.days, 7);
                    assert.equal(geometry.fontSize, `${size}px`);
                    await check({ page, theme, sidebar, size, ...geometry });
                    await style.evaluate(node => node.remove());
                }
            } finally {
                try {
                    if (page) await page.close();
                } finally {
                    deleteFixture("leftovers-calendar", fixture.user);
                }
            }
        }
    } finally {
        await browser.close();
    }
}

if (require.main === module) {
    (async () => {
        const failures = [];
        for (const width of [15, 18]) {
            await runCalendarCases(width, [16, 20, 24], ({ theme, sidebar, size, box, tableBox }) => {
                const message = `${theme}, ${sidebar}, ${width}em, ${size}px: calendar fits inside its module`;
                const overflow = Math.max(box.left - tableBox.left, tableBox.right - box.right);
                if (overflow > 0.5) failures.push(`${message} (overflows by ${overflow.toFixed(1)}px)`);
                else console.log(`PASS: ${message}`);
            });
        }
        assert.deepEqual(failures, []);
    })().catch(error => {
        console.error(error);
        process.exitCode = 1;
    });
}

module.exports = { runCalendarCases };
