// t/browser/userpicfactory.js
//
// Browser regression for responsive icon cropping and touch input.
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
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { BASE, launch, createFixture, deleteFixture, login } = require("./lib/browser");

async function makePhoto(page, file) {
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="800" height="600">
        <rect width="800" height="600" fill="#b2dced"/>
        <path d="M0 440 L195 230 327 373 520 166 800 445V600H0Z" fill="#745d92"/>
        <circle cx="230" cy="155" r="87" fill="#f5b844"/>
        <path d="M0 490 Q210 350 435 505 T800 500V600H0Z" fill="#297c73"/>
        <path d="M548 115 q30 -36 60 0 q30 -36 60 0 M641 152 q18 -24 36 0 q18 -24 36 0"
            fill="none" stroke="#415477" stroke-width="7" stroke-linecap="round"/>
    </svg>`;
    const photo = await page.evaluate(async source => {
        const image = new Image();
        image.src = "data:image/svg+xml," + encodeURIComponent(source);
        await image.decode();
        const canvas = document.createElement("canvas");
        canvas.width = image.width;
        canvas.height = image.height;
        canvas.getContext("2d").drawImage(image, 0, 0);
        return canvas.toDataURL("image/png").split(",")[1];
    }, svg);
    fs.writeFileSync(file, Buffer.from(photo, "base64"));
}

async function withFixture(run) {
    const folder = fs.mkdtempSync(path.join(os.tmpdir(), "dw-icon-crop-"));
    const photo = path.join(folder, "sample-landscape.png");
    let browser, fixture;
    try {
        fixture = createFixture("userpicfactory");
        browser = await launch();
        const page = await browser.newPage();
        await makePhoto(page, photo);
        await page.close();
        const cookies = await login(browser, fixture.user, fixture.password);
        await run(browser, cookies, photo);
    } finally {
        try {
            if (browser) await browser.close();
        } finally {
            try {
                if (fixture) deleteFixture("userpicfactory", fixture.user);
            } finally {
                fs.rmSync(folder, { recursive: true, force: true });
            }
        }
    }
}

async function submit(page, selector) {
    await Promise.all([
        page.waitForNavigation({ waitUntil: "networkidle2" }),
        page.$eval(selector, button => button.click()),
    ]);
}

async function openUpload(page, cookies, photo, scheme, keyword) {
    await page.setCookie(...cookies, { name: "BMLschemepref", value: scheme, url: BASE });
    assert.equal((await page.goto(BASE + "/manage/icons", { waitUntil: "networkidle2" })).status(), 200);
    await (await page.waitForSelector("#userpic_0")).uploadFile(photo);
    await page.type("#keywords_0", keyword);
}

async function openFactory(page) {
    await submit(page, '#uploadPic input[type="submit"]');
    assert.equal(new URL(page.url()).pathname, "/tools/userpicfactory");
    await page.waitForFunction(() => document.querySelector("#userpic")?.naturalWidth && window.regsel);
}

const cropBox = page => page.$eval("#userpic", img => img.getBoundingClientRect().toJSON());
const selection = page => page.$$eval("#x1, #y1, #x2, #y2", inputs => inputs.map(input => Number(input.value)));

async function checkMobile(browser, cookies, photo) {
    const page = await browser.newPage();
    try {
        const viewport = { width: 390, height: 844, isMobile: true, hasTouch: true };
        await page.setViewport(viewport);
        const keyword = "Touch crop";
        await openUpload(page, cookies, photo, "tropo-red", keyword);
        await openFactory(page);
        await page.$eval("#userpic", img => img.scrollIntoView({ block: "center", inline: "start" }));
        const { left, right, top, width, height } = await cropBox(page);
        const before = await selection(page);
        const start = { x: left + width * 0.22, y: top + height * 0.13 };
        const end = { x: Math.min(left + width * 0.45, 350), y: top + height * 0.38 };
        const finger = await page.touchscreen.touchStart(start.x, start.y);
        await finger.move(end.x, end.y);
        await finger.end();
        const picked = await selection(page);
        assert.deepEqual({
            fitsViewport: left >= 0 && right <= viewport.width,
            touchChangesSelection: picked.some((value, index) => value !== before[index]),
        }, { fitsViewport: true, touchChangesSelection: true });

        const expected = [0.22 * 640, 0.13 * 480, 0.45 * 640, 0.38 * 480];
        for (const [index, value] of picked.entries()) {
            assert.ok(Math.abs(value - expected[index]) < 4, "touch maps back to full-size preview pixels");
        }
        assert.ok(await page.$eval("#prevcon", preview => preview.getBoundingClientRect().width >= 98),
            "the crop preview remains at icon size");

        const preview = () => page.$eval("#userpicpreview", img => img.getBoundingClientRect().toJSON());
        const committedPreview = await preview();
        const client = await page.createCDPSession();
        await client.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [start] });
        await client.send("Input.dispatchTouchEvent", {
            type: "touchMove", touchPoints: [{ x: end.x + 25, y: end.y + 35 }],
        });
        assert.notDeepEqual(await preview(), committedPreview, "the preview updates during the drag");
        await client.send("Input.dispatchTouchEvent", { type: "touchCancel", touchPoints: [] });
        assert.deepEqual(await selection(page), picked, "cancel leaves the last completed crop intact");
        assert.deepEqual(await preview(), committedPreview, "cancel restores the previous preview");

        await page.setViewport({ ...viewport, width: 320 });
        assert.deepEqual(await selection(page), picked, "a viewport resize preserves the selected image pixels");
        assert.ok((await cropBox(page)).right <= 320, "the image fits after resizing to 320px");

        await submit(page, "#createbtn");
        const saved = await page.waitForFunction(label => {
            const row = [...document.querySelectorAll(".userpic_wrapper")].find(wrapper =>
                wrapper.querySelector('.userpic_keywords input[type="text"]')?.value === label);
            const img = row?.querySelector(".EditIconsUserpic img");
            return img?.naturalWidth > 0 && img;
        }, {}, keyword);
        const icon = await saved.evaluate(img => {
            const canvas = document.createElement("canvas");
            canvas.getContext("2d").drawImage(img, 0, 0);
            return { width: img.naturalWidth, height: img.naturalHeight,
                center: [...canvas.getContext("2d").getImageData(50, 40, 1, 1).data] };
        });
        assert.equal(icon.width, 100);
        assert.ok(Math.abs(icon.height - 82) <= 3, "the saved icon has the selected aspect ratio");
        assert.ok(icon.center[0] > 225 && icon.center[2] < 100, "the saved icon contains the yellow sun");
        console.log("PASS: touch crop fits, maps to image pixels, survives cancel/resize, and saves the selected image");
    } finally {
        await page.close();
    }
}

async function checkDesktop(browser, cookies, photo) {
    const page = await browser.newPage();
    try {
        await openUpload(page, cookies, photo, "gradation-vertical-local", "Mouse crop");
        await openFactory(page);
        await page.$eval("#userpic", img => img.scrollIntoView({ block: "center" }));
        const { left, top, width, height } = await cropBox(page);
        assert.equal(width, 640, "the desktop image remains full size");
        await page.mouse.move(left + 50, top + height - 80);
        await page.keyboard.down("Shift");
        await page.mouse.down();
        await page.mouse.move(left + 250, top + height + 20, { steps: 5 });
        await page.mouse.up();
        await page.keyboard.up("Shift");
        const [x1, y1, x2, y2] = await selection(page);
        assert.ok(Math.abs(x1 - 50) <= 1 && Math.abs(y1 - 400) <= 1, "mouse drag starts at the pointer");
        assert.ok(y2 <= height && x2 > x1 && Math.abs((x2 - x1) - (y2 - y1)) <= 1,
            "dragging past the edge still commits a square inside the image");
        console.log("PASS: desktop mouse and Shift work outside the image bounds");
    } finally {
        await page.close();
    }
}

if (require.main === module) {
    withFixture(async (...args) => {
        const failures = [];
        for (const check of [checkMobile, checkDesktop]) {
            try {
                await check(...args);
            } catch (error) {
                failures.push(error);
                console.error(error);
            }
        }
        if (failures.length) process.exitCode = 1;
    }).catch(error => {
        console.error(error);
        process.exitCode = 1;
    });
}

module.exports = { withFixture, openUpload, openFactory, submit, cropBox, selection };
