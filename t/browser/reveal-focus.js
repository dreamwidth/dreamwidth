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

async function focusInside(page, selector) {
    return page.$eval(selector, (element) => element.contains(document.activeElement));
}

async function assertNotModal(page, selector) {
    assert.equal(await page.$eval(selector, (element) => element.hasAttribute("aria-modal")), false);
}

async function openingFocus(page) {
    await page.$eval(modal, (dialog) => {
        const settings = window.jQuery(dialog).data("reveal-init");
        window.jQuery(dialog).data("reveal-init", { ...settings, animation_speed: 1200 });
    });
    await page.focus(trigger);
    await page.keyboard.press("Enter");
    await page.keyboard.press("Tab");
    const earlyTab = await page.evaluate((opener) => document.activeElement.matches(opener), trigger);
    await page.waitForFunction((selector) => {
        const dialog = document.querySelector(selector);
        return dialog.classList.contains("open") && getComputedStyle(dialog).opacity !== "1";
    }, {}, modal);
    await page.$eval(modal, (dialog) => {
        document.addEventListener("focusin", ({ target }) => {
            window.openingTabFocus = {
                inside: dialog.contains(target),
                animating: getComputedStyle(dialog).opacity !== "1",
                hidden: !!target.closest('[aria-hidden="true"]'),
                modal: dialog.getAttribute("aria-modal"),
            };
        }, { once: true });
    });
    await page.keyboard.press("Tab");
    const focusedDuringTab = await page.evaluate(() => window.openingTabFocus);
    assert.equal(earlyTab, true, "Tab stays on the opener while the dialog is not yet visible");
    assert.deepEqual(focusedDuringTab, { inside: true, animating: true, hidden: false, modal: "true" },
        "as Tab moves focus inside, the still-animating dialog is exposed as modal");
}

async function invalidOpener(page) {
    const results = [];
    for (const invalidate of ["remove", "hide", "disable"]) {
        await page.reload({ waitUntil: "networkidle2" });
        if (invalidate === "disable") {
            await page.$eval(trigger, (opener) => {
                const button = document.createElement("button");
                button.setAttribute("data-reveal-id", opener.getAttribute("data-reveal-id"));
                button.textContent = opener.textContent;
                opener.replaceWith(button);
            });
        }
        await open(page);
        await page.$eval(trigger, (opener, action) => {
            if (action === "remove") opener.remove();
            if (action === "hide") opener.hidden = true;
            if (action === "disable") opener.disabled = true;
        }, invalidate);
        await page.keyboard.press("Escape");
        await page.waitForSelector(modal, { hidden: true });
        await assertNotModal(page, modal);
        results.push(await page.evaluate(() => document.activeElement.matches("#content, main")));
    }
    assert.deepEqual(results, [true, true, true], "removed, hidden, and disabled openers fall back to the main content");
}

async function dialogTransition(page, stack, closeWithEscape = false) {
    await page.$eval(modal, (dialog, stack, closeWithEscape) => {
        const settings = { ...window.jQuery(dialog).data("reveal-init"), multiple_opened: stack, animation: "none" };
        window.jQuery(dialog).data("reveal-init", settings);
        dialog.insertAdjacentHTML("beforeend", '<button type="button" id="next-dialog" data-reveal-id="second-dialog">Next</button>');
        document.body.insertAdjacentHTML("beforeend", '<div class="reveal-modal" id="second-dialog" data-reveal aria-hidden="true"><button type="button" class="close-reveal-modal">Close</button></div>');
        window.jQuery("#second-dialog").data("reveal-init", {
            ...settings, animation: "fade", close_on_esc: !stack || closeWithEscape,
        });
    }, stack, closeWithEscape);
    await open(page);
    await page.focus("#next-dialog");
    await page.evaluate((selector) => {
        window.pageFocusDuringTransition = false;
        document.addEventListener("focusin", (event) => {
            if (event.target.matches(selector)) window.pageFocusDuringTransition = true;
        });
    }, trigger);
    await page.keyboard.press("Enter");
    const second = "#second-dialog";
    await waitUntilOpen(page, second);
    assert.equal(await page.evaluate(() => window.pageFocusDuringTransition), false,
        "opening a second dialog does not restore focus to the page in between");
    await assertNotModal(page, modal);
    assert.equal(await page.$eval(second, (dialog) => dialog.getAttribute("aria-modal")), "true");
    if (closeWithEscape) {
        await page.keyboard.press("Escape");
    } else {
        await page.click(`${second} .close-reveal-modal`);
    }
    await assertClosed(page, second, stack ? "#next-dialog" : trigger);
    await assertNotModal(page, second);
    if (stack) {
        assert.equal(await page.$eval(modal, (dialog) => dialog.getAttribute("aria-modal")), "true");
        await page.keyboard.press("Escape");
        await page.waitForSelector(modal, { hidden: true, timeout: 3000 });
        await assertClosed(page);
        await assertNotModal(page, modal);
    }
}

async function dynamicControls(page) {
    await open(page);
    await page.$eval(modal, (dialog) => {
        dialog.querySelectorAll("input, button, a[href]").forEach((control) => { control.tabIndex = -1; });
        dialog.insertAdjacentHTML("beforeend", `
            <button type="button" id="first-stop">First</button>
            <button type="button" disabled>Disabled</button>
            <input type="radio" name="focus-test" id="radio-unchecked">
            <input type="radio" name="focus-test" id="radio-checked" checked>
            <button type="button" id="last-stop">Last</button>`);
    });
    await page.focus("#first-stop");
    await page.keyboard.press("Tab");
    assert.equal(await page.evaluate(() => document.activeElement.id), "radio-checked");
    await page.keyboard.press("Tab");
    assert.equal(await page.evaluate(() => document.activeElement.id), "last-stop");
    await page.$eval("#first-stop", (button) => { button.disabled = true; });
    await page.keyboard.press("Tab");
    assert.equal(await page.evaluate(() => document.activeElement.id), "radio-checked");
}

async function browseIcons(page) {
    await page.addScriptTag({ url: `${BASE}/js/components/jquery.icon-browser.js` });
    await page.evaluate(() => {
        document.body.insertAdjacentHTML("beforeend", `
            <button type="button" id="browse-icons">Browse Icons</button>
            <select id="reply-icon"><option value="">Default</option><option value="test">Test</option></select>
            <textarea id="reply-body"></textarea>
            <div class="reveal-modal" id="icon-picker" data-reveal aria-hidden="true">
                <input id="js-icon-browser-search" type="search" aria-label="Search">
                <div id="js-icon-browser-content"><ul></ul></div>
                <button type="button" class="close-reveal-modal">Close</button>
            </div>`);
        window.jQuery("#reply-icon").iconBrowser({
            triggerSelector: "#browse-icons", modalId: "icon-picker",
            focusAfterBrowse: "#reply-body", preferences: {},
        });
    });
    await page.setRequestInterception(true);
    page.on("request", (request) => {
        if (!new URL(request.url()).pathname.endsWith("/__rpc_userpicselect")) return request.continue();
        return request.respond({
            contentType: "application/json",
            body: JSON.stringify({ ids: [1], pics: { 1: {
                url: "data:image/gif;base64,R0lGODlhAQABAIAAAAUEBAAAACwAAAAAAQABAAACAkQBADs=",
                keywords: ["test"], alt: "Test icon", comment: "", width: 1, height: 1,
            } } }),
        });
    });
    const picker = "#icon-picker";
    const opener = "#browse-icons";
    await page.click(opener);
    await waitUntilOpen(page, picker);
    const icon = `${picker} .icon-browser-icon-button`;
    await page.waitForSelector(icon, { visible: true });
    await page.focus("#js-icon-browser-search");
    await page.keyboard.press("Tab");
    assert.equal(await focusInside(page, icon), true, "AJAX-loaded icon joins the Tab cycle");
    await page.keyboard.press("Enter");
    await page.waitForSelector(picker, { hidden: true });
    assert.equal(await page.$eval("#reply-icon", (select) => select.value), "test");
    const selectionFocus = await focusInside(page, "#reply-body");
    for (const dismiss of [
        () => page.keyboard.press("Escape"),
        () => page.click(`${picker} .close-reveal-modal`),
        () => page.mouse.click(5, 950),
    ]) {
        await page.click(opener);
        await waitUntilOpen(page, picker);
        await dismiss();
        await assertClosed(page, picker, opener);
        await assertNotModal(page, picker);
    }
    assert.equal(selectionFocus, true, "selecting an icon returns focus to the comment body");
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

        const failures = [];
        for (const [name, check] of [
            ["opening animation", openingFocus],
            ["invalidated opener", invalidOpener],
            ["replacement dialog", (page) => dialogTransition(page, false)],
            ["stacked dialog: Escape twice", (page) => dialogTransition(page, true, true)],
            ["stacked dialog: Close then Escape", (page) => dialogTransition(page, true)],
            ["dynamic, disabled, and radio controls", dynamicControls],
            ["Browse Icons selection and dismissal", browseIcons],
        ]) {
            const scenario = await browser.newPage();
            try {
                await scenario.goto(`${BASE}/site/?skin=celerity`, { waitUntil: "networkidle2" });
                await check(scenario);
                console.log(`PASS: ${name}`);
            } catch (error) {
                console.error(`FAIL: ${name}`, error);
                failures.push(name);
            } finally {
                await scenario.close();
            }
        }
        assert.deepEqual(failures, [], "Reveal focus regressions");
    } finally {
        await browser.close();
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
