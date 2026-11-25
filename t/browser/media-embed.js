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
const { spawn } = require("node:child_process");
const { once } = require("node:events");
const net = require("node:net");
const path = require("node:path");
const { setTimeout: delay } = require("node:timers/promises");

async function withMediaServer(fixtureScript, run) {
    const socket = net.createServer().listen(0, "127.0.0.1");
    await once(socket, "listening");
    const { port } = socket.address();
    await new Promise(resolve => socket.close(resolve));

    const server = spawn("perl", [fixtureScript, "--serve", String(port)], { stdio: "inherit" });
    const closed = once(server, "close");
    try {
        for (let attempt = 0; attempt < 60; attempt++) {
            const response = await fetch(`http://127.0.0.1:${port}/`, {
                signal: AbortSignal.timeout(1000),
            }).catch(() => null);
            if (response?.ok) {
                await response.body.cancel();
                return await run("http://www.dw-embed.test", [
                    `--host-resolver-rules=MAP *.dw-embed.test 127.0.0.1:${port}`,
                ]);
            }
            if (server.exitCode !== null) break;
            await delay(250);
        }
        throw new Error("Media fixture server did not start");
    } finally {
        server.kill();
        await closed;
    }
}

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

async function checkImage(page, src, width, height) {
    const url = new URL(src, page.url()).href;
    const probe = await page.browser().newPage();
    try {
        await probe.setCacheEnabled(false);
        const response = await probe.goto(url, { referer: page.url(), waitUntil: "load" });
        assert.equal(response.url(), url);
        assert.equal(response.status(), 200, url);
        assert.match(response.headers()["content-type"], /^image\/png\b/, url);
        assert.equal(new URL(response.request().headers().referer).origin, new URL(page.url()).origin);
        const dimensions = await probe.$eval("img", async image => {
            await image.decode();
            return [image.naturalWidth, image.naturalHeight];
        });
        assert.deepEqual(dimensions, [width, height], url);
    } finally {
        await probe.close();
    }
}

async function checkEmbeds(args) {
    const { BASE, launch, createFixture, deleteFixture, login } = require("./lib/browser");
    const fixture = createFixture("media-embed");
    let browser;
    try {
        browser = await launch(args);
        const cookies = await login(browser, fixture.user, fixture.password);
        const page = await browser.newPage();
        await page.setCookie(...cookies);
        await page.setCacheEnabled(false);

        for (const view of ["list", "grid"]) {
            const response = await page.goto(`${BASE}/file/list?view=${view}`, { waitUntil: "load" });
            assert.equal(response.status(), 200);
            const thumb = `#embed-thumb-${fixture.large}`;
            const select = `#thumbnail_sizes-${fixture.large}`;
            const initial = await embed(page, thumb);
            assert.match(initial.src, /\/file\/320x320\/\d+\.png$/, `${view}: thumbnail starts at 320px`);
            assert.equal(await page.$eval(select, input => input.value), "320", `${view}: picker matches`);
            assert.match(initial.href, /\/file\/\d+\.png$/, `${view}: link opens the original`);
            await checkImage(page, initial.src, 320, 200);
            await page.select(select, "original");
            const originalThumb = await embed(page, thumb);
            assert.deepEqual(originalThumb, { ...initial, src: initial.href }, `${view}: original keeps the link`);
            await checkImage(page, originalThumb.src, 1440, 900);
            await page.select(select, "640");
            const resized = await embed(page, thumb);
            assert.match(resized.src, /\/file\/640x640\/\d+\.png$/, `${view}: can switch back to a size`);
            assert.equal(resized.href, initial.href, `${view}: resizing leaves the original link alone`);
            assert.equal(resized.alt, "1440x900 gradient: blue & gold", `${view}: resizing preserves alt text`);
            await checkImage(page, resized.src, 640, 400);
            const smallThumb = await embed(page, `#embed-thumb-${fixture.small}`);
            assert.match(smallThumb.src, /\/file\/320x320\/\d+\.png$/);
            await checkImage(page, smallThumb.src, 240, 180);

            if (view === "list") {
                const field = `#embed-full-${fixture.large}`;
                const imageSelect = `#image_sizes-${fixture.large}`;
                const image = await embed(page, field);
                assert.match(image.src, /\/file\/800x800\/\d+\.png$/, "list: inline image starts at 800px");
                assert.equal(image.href, undefined, "list: inline image remains unlinked");
                await checkImage(page, image.src, 800, 500);
                await page.select(imageSelect, "original");
                const original = await embed(page, field);
                assert.equal(original.src, initial.href, "list: original remains available as an inline embed");
                await checkImage(page, original.src, 1440, 900);
                assert.deepEqual(await embed(page, thumb), resized, "list: image picker only changes its own embed");
                await page.select(imageSelect, "800");
                assert.deepEqual(await embed(page, field), image, "list: can switch from original back to a size");
                const smallImage = await embed(page, `#embed-full-${fixture.small}`);
                assert.match(smallImage.src, /\/file\/800x800\/\d+\.png$/);
                await checkImage(page, smallImage.src, 240, 180);
            }
            console.log(`PASS: ${view} embed defaults, picker and delivered image dimensions`);
        }
    } finally {
        try {
            if (browser) await browser.close();
        } finally {
            deleteFixture("media-embed", fixture.user);
        }
    }
}

if (require.main === module) {
    withMediaServer(path.join(__dirname, "fixtures", "media-embed.pl"), async (base, args) => {
        process.env.DW_BROWSER_BASE = base;
        await checkEmbeds(args);
    }).catch(error => {
        console.error(error);
        process.exitCode = 1;
    });
}

module.exports = { withMediaServer, embed };
