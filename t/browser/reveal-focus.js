// t/browser/reveal-focus.js
// Verify keyboard focus and dismissal of the navigation login dialog.
//
// Authors:
//      Dreamwidth contributors
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself. For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

"use strict";

const assert = require("node:assert/strict");
const { BASE, launch } = require("./lib/browser");

const modal = "#nav-login-form";
const trigger = `#account-links [data-reveal-id="${modal.slice(1)}"]`;
const closeButton = `${modal} .close-reveal-modal`;

async function cycle(page, backwards) {
    const visited = [];
    if (backwards) await page.keyboard.down("Shift");
    try {
        for (let step = 0; step < 7; step++) {
            await page.keyboard.press("Tab");
            visited.push(await page.evaluate((selector) => {
                const active = document.activeElement;
                return {
                    inside: !!active.closest(selector),
                    label: active.id || active.getAttribute("aria-label") || active.textContent.trim().slice(0, 40),
                };
            }, modal));
        }
    } finally {
        if (backwards) await page.keyboard.up("Shift");
    }
    return visited;
}

async function waitUntilOpen(page, selector = modal) {
    await page.waitForFunction((selector) => {
        const dialog = document.querySelector(selector);
        return dialog.classList.contains("open") && getComputedStyle(dialog).opacity === "1";
    }, {}, selector);
}

async function open(page) {
    await page.focus(trigger);
    await page.keyboard.press("Enter");
    await waitUntilOpen(page);
}

async function assertClosed(page, dialogSelector = modal, opener = trigger) {
    await page.waitForSelector(dialogSelector, { hidden: true });
    assert.equal(await page.$eval(dialogSelector, (dialog) => dialog.getAttribute("aria-hidden")), "true");
    assert.equal(await page.$eval(opener, (element) => element === document.activeElement), true,
        "dismissing the dialog returns focus to its trigger");
}

async function main() {
    const browser = await launch();
    try {
        const page = await browser.newPage();
        await page.goto(`${BASE}/site/?skin=celerity`, { waitUntil: "networkidle2" });
        await open(page);
        assert.equal(await page.$eval(modal, (dialog) => dialog.contains(document.activeElement)), true,
            "opening the dialog moves focus inside");

        const forward = await cycle(page, false);
        await page.focus(`${modal} #login_user`);
        const backward = await cycle(page, true);
        assert.ok([...forward, ...backward].every((item) => item.inside),
            `focus escaped while the dialog was open: ${JSON.stringify({ forward, backward })}`);
        assert.equal(forward[5].label, "Close");
        assert.equal(forward[6].label, "login_user");
        assert.equal(backward[0].label, "Close");
        assert.equal(backward[6].label, "login_user");

        const semantics = await page.$eval(modal, (dialog) => ({
            role: dialog.getAttribute("role"),
            modal: dialog.getAttribute("aria-modal"),
            hidden: dialog.getAttribute("aria-hidden"),
            label: dialog.getAttribute("aria-label"),
        }));
        assert.deepEqual(semantics, { role: "dialog", modal: "true", hidden: "false", label: "Log in" });
        console.log("PASS: login dialog keeps forward and reverse Tab focus inside and has dialog semantics");

        await page.keyboard.press("Escape");
        await assertClosed(page);
        await open(page);
        await page.click(closeButton);
        await assertClosed(page);
        await open(page);
        await page.mouse.click(5, 950);
        await assertClosed(page);
        console.log("PASS: Escape, close button, and backdrop close the dialog and return focus to its trigger");

        await page.goto(`${BASE}/entry/new?skin=celerity`, { waitUntil: "networkidle2" });
        const entryModal = "#js-post-entry-login";
        const entryTrigger = '#js-post-entry [data-reveal-id="js-post-entry-login"]';
        await page.waitForSelector(entryTrigger, { visible: true });
        await page.$eval(entryModal, (dialog) => {
            dialog.querySelectorAll("input, button, a[href]").forEach((control) => { control.tabIndex = -1; });
        });
        await page.focus(entryTrigger);
        await page.$eval(entryModal, (dialog) => window.jQuery(dialog).foundation("reveal", "open"));
        await waitUntilOpen(page, entryModal);
        for (const key of ["Tab", "Shift+Tab"]) {
            assert.equal(await page.$eval(entryModal, (dialog) => dialog === document.activeElement), true,
                "the dialog itself holds focus when it has no tabbable controls");
            if (key === "Shift+Tab") await page.keyboard.down("Shift");
            await page.keyboard.press("Tab");
            if (key === "Shift+Tab") await page.keyboard.up("Shift");
        }
        assert.equal(await page.$eval(entryModal, (dialog) => dialog === document.activeElement), true);
        await page.keyboard.press("Escape");
        await assertClosed(page, entryModal, entryTrigger);
        console.log("PASS: a programmatically opened dialog with no tabbable controls holds and restores focus");
    } finally {
        await browser.close();
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
