// t/browser/lib/entry-edit-submit.js
// Run the rendered entry edit form in Chrome and return its POST body to the
// in-process PSGI test, where external crosspost jobs can be observed safely.
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

const { readFileSync } = require("node:fs");
const { launch } = require("./browser");

async function submit(filename, url, visibility, edit, editorMode) {
    const draftSwitch = editorMode === "draft-switch";
    const roundTrip = editorMode === "roundtrip";
    const delayEditor = editorMode === "delay" || roundTrip;
    const fallbackEditor = editorMode === "fallback";
    const origin = new URL(url).origin;
    const html = readFileSync(filename, "utf8")
        .replace(/(?:https?:)?\/\/www\.test\.dw(?=\/)/g, origin);
    const browser = await launch();
    try {
        const page = await browser.newPage();
        if (fallbackEditor) {
            await page.evaluateOnNewDocument(() => {
                Object.defineProperty(navigator, "productSub", { value: "0" });
                Object.defineProperty(navigator, "userAgent", { value: "Unsupported browser" });
            });
        }
        const isLocal = request => new URL(request.url()).origin === origin;
        const isEditorFrame = request => request.isNavigationRequest()
            && new URL(request.url()).pathname.endsWith("/fck/editor/fckeditor.html");
        page.on("pageerror", error => console.error(error.message));
        page.on("requestfailed", request => {
            if (request.method() === "GET" && isLocal(request) && !(delayEditor && isEditorFrame(request))) {
                console.error(request.failure().errorText, request.url());
            }
        });
        await page.setRequestInterception(true);
        page.on("request", request => {
            if (request.isNavigationRequest() && request.frame() === page.mainFrame()) {
                if (request.url() === url && request.method() === "GET") {
                    return request.respond({ contentType: "text/html; charset=utf-8", body: html });
                }
                return request.abort();
            }
            if (delayEditor && isEditorFrame(request)) {
                return;
            }
            return request.method() === "GET" && isLocal(request) ? request.continue() : request.abort();
        });
        const editorRequest = delayEditor && page.waitForRequest(isEditorFrame);
        const navigation = page.goto(url, { waitUntil: "domcontentloaded" });
        if (delayEditor) {
            await Promise.race([editorRequest, navigation]);
            await editorRequest;
            if (await page.evaluate(() => window.FCKeditor_LOADED)) {
                throw new Error("Rich-text editor loaded before the early save");
            }
        } else if (fallbackEditor) {
            await navigation;
            await page.waitForSelector("#entry-body", { visible: true });
            if (await page.evaluate(() => FCKeditor_IsCompatibleBrowser()
                || document.getElementById("entry-body___Frame"))) {
                throw new Error("FCKeditor did not leave the fallback textarea in place");
            }
        } else if (draftSwitch) {
            await navigation;
            await page.waitForFunction(() => {
                const frame = document.getElementById("entry-body___Frame");
                const editor = window.FCKeditorAPI?.GetInstance("entry-body");
                return editor && editor.Status === frame.contentWindow.FCK_STATUS_COMPLETE;
            });
        } else {
            await navigation;
            await page.waitForFunction(() => window.FCKeditor_LOADED);
        }
        if (roundTrip) {
            await page.select("#editor", "html_casual1");
            await page.select("#editor", "rte0");
        }
        if (edit && fallbackEditor) {
            await page.type("#entry-body", edit);
        } else if (edit) {
            await page.evaluate(() => FCKeditorAPI.GetInstance("entry-body").Focus());
            await page.keyboard.type(edit);
        }
        if (draftSwitch) {
            if (!await page.evaluate(() => should_init === true && LJDraft.timer != null)) {
                throw new Error("Rich-text input did not schedule draft autosave");
            }
            await page.select("#editor", "html_casual1");
            await page.waitForSelector("#entry-body", { visible: true });
            process.stdout.write(await page.$eval("#entry-body", body => body.value));
            return;
        }
        await page.select("#hide_crosspost_links", visibility);
        const [request] = await Promise.all([
            page.waitForRequest(request => request.method() === "POST"
                && request.isNavigationRequest() && request.frame() === page.mainFrame()),
            page.click('input[name="action:post"].left'),
        ]);
        process.stdout.write(await request.fetchPostData());
    } finally {
        await browser.close();
    }
}

submit(...process.argv.slice(2)).catch(error => {
    console.error(error);
    process.exitCode = 1;
});
