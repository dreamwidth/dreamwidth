// t/browser/lib/browser.js
//
// Shared helpers for the manual browser tests in t/browser: launch Chrome,
// create and remove fixtures, and log in to the local dev server.
//
// Authors:
//      Mark Smith <mark@dreamwidth.org>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself. For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

"use strict";

const { execFileSync } = require("node:child_process");
const path = require("node:path");
const puppeteer = require("/opt/dw-screenshot/node_modules/puppeteer-core");

const BASE = process.env.DW_BROWSER_BASE || "http://127.0.0.1:8080";
const FIXTURES = path.join(__dirname, "..", "fixtures");

function launch() {
    return puppeteer.launch({
        executablePath: "/usr/bin/google-chrome-stable",
        args: ["--no-sandbox", "--disable-gpu"],
        defaultViewport: { width: 1280, height: 1000 },
    });
}

// Run t/browser/fixtures/<name>.pl and return the JSON it prints.
function createFixture(name) {
    const out = execFileSync("perl", [path.join(FIXTURES, name + ".pl")], { encoding: "utf8" });
    return JSON.parse(out);
}

function deleteFixture(name, user) {
    execFileSync("perl", [path.join(FIXTURES, name + ".pl"), "--delete", user]);
}

// Log in through the mobile login form and return the session cookies.
async function login(browser, user, password) {
    const page = await browser.newPage();
    try {
        await page.goto(BASE + "/mobile/login", { waitUntil: "networkidle2", timeout: 30000 });
        await page.type('input[name="user"]', user);
        await page.type('input[name="password"]', password);
        await Promise.all([
            page.waitForNavigation({ waitUntil: "networkidle2", timeout: 30000 }),
            page.$eval('input[name="password"]', (input) => input.form.submit()),
        ]);
        const cookies = await page.cookies();
        if (!cookies.some((c) => c.name === "ljmastersession")) {
            throw new Error("login as " + user + " did not set a session");
        }
        return cookies;
    } finally {
        await page.close();
    }
}

module.exports = { BASE, launch, createFixture, deleteFixture, login };
