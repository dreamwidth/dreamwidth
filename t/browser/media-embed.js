// t/browser/media-embed.js
//
// Check the copyable image embed sizes in both image hosting layouts.
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

async function embed(page, selector) {
    return page.$eval(selector, input => {
        const html = new DOMParser().parseFromString(input.value, "text/html");
        const img = html.querySelector("img");
        return {
            src: img.getAttribute("src"),
            alt: img.alt,
            href: html.querySelector("a")?.getAttribute("href"),
        };
    });
}

async function main() {
    const fixture = createFixture("media-embed");
    let browser;
    try {
        browser = await launch();
        const cookies = await login(browser, fixture.user, fixture.password);
        const page = await browser.newPage();
        await page.setCookie(...cookies);

        for (const view of ["list", "grid"]) {
            const response = await page.goto(`${BASE}/file/list?view=${view}`, { waitUntil: "load" });
            assert.equal(response.status(), 200);
            const thumb = 'input[id^="embed-thumb-"]';
            const select = 'select[id^="thumbnail_sizes-"]';
            const initial = await embed(page, thumb);
            assert.match(initial.src, /\/file\/320x320\/\d+\.png$/, `${view}: thumbnail starts at 320px`);
            assert.equal(await page.$eval(select, input => input.value), "320", `${view}: picker matches`);
            assert.match(initial.href, /\/file\/\d+\.png$/, `${view}: link opens the original`);
            await page.select(select, "100");
            const smaller = await embed(page, thumb);
            assert.match(smaller.src, /\/file\/100x100\/\d+\.png$/, `${view}: picker changes copied size`);
            assert.equal(smaller.href, initial.href, `${view}: resizing leaves the original link alone`);
            assert.equal(smaller.alt, "1440x900 gradient: blue & gold", `${view}: resizing preserves alt text`);

            if (view === "list") {
                const field = 'input[id^="embed-full-"]';
                const imageSelect = 'select[id^="image_sizes-"]';
                const image = await embed(page, field);
                assert.match(image.src, /\/file\/800x800\/\d+\.png$/, "list: inline image starts at 800px");
                assert.equal(image.href, undefined, "list: inline image remains unlinked");
                await page.select(imageSelect, "original");
                const original = await embed(page, field);
                assert.equal(original.src, initial.href, "list: original remains available as an inline embed");
                assert.deepEqual(await embed(page, thumb), smaller, "list: image picker only changes its own embed");
                await page.select(imageSelect, "800");
                assert.deepEqual(await embed(page, field), image, "list: can switch from original back to a size");
            }
            console.log(`PASS: ${view} embed defaults and picker`);
        }
    } finally {
        try {
            if (browser) await browser.close();
        } finally {
            deleteFixture("media-embed", fixture.user);
        }
    }
}

main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
