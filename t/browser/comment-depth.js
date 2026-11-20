// t/browser/comment-depth.js
//
// Check the comment depth displayed when expanding a collapsed thread.
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
const { BASE, launch, createFixture, deleteFixture } = require("./lib/browser");

function commentState(page, id) {
    return page.$eval(`#cmt${id}`, comment => {
        const depth = comment.querySelector(".thread-depth");
        return {
            wrapperDepth: Number(comment.parentElement.dataset.commentDepth),
            indicatorDepth: Number(depth.textContent.match(/\d+$/)[0]),
            mobileIndent: depth.classList.contains("indent-mobile"),
            expanded: Boolean(comment.querySelector(".comment-content")),
        };
    });
}

async function checkExpansion(page, url, fixture, depth) {
    const response = await page.goto(url, { waitUntil: "networkidle2" });
    assert.equal(response.status(), 200);
    const target = `#cmt${fixture.target}`;
    const child = `#cmt${fixture.child}`;
    for (const [id, expectedDepth] of [[fixture.target, depth], [fixture.child, depth + 1]]) {
        assert.deepEqual(await commentState(page, id), {
            wrapperDepth: expectedDepth, indicatorDepth: expectedDepth, mobileIndent: false, expanded: false,
        }, `comment ${id} starts collapsed at depth ${expectedDepth}`);
    }

    await page.click(`${target} a[onclick*="Expander.make"]`);
    await page.waitForSelector(`${target} .comment-content`);
    await page.waitForSelector(`${child} .comment-content`);
    const states = [];
    for (const id of [fixture.target, fixture.child]) {
        states.push(await commentState(page, id));
    }
    return states;
}

(async () => {
    const fixture = createFixture("comment-depth");
    let browser;
    try {
        browser = await launch();
        const page = await browser.newPage();
        await page.setViewport({ width: 390, height: 844 });
        const entryURL = BASE + fixture.path;
        const fromEntry = await checkExpansion(page, entryURL, fixture, 3);
        const fromThread = await checkExpansion(page, `${entryURL}?thread=${fixture.middle}`, fixture, 2);
        const fromMalformedThread = await checkExpansion(page, `${entryURL}?thread=${fixture.middle}.0`, fixture, 3);
        const malformedReplyHref = await page.$eval(
            `#cmt${fixture.middle} a[href*="replyto="]`,
            a => a.getAttribute("href")
        );
        assert.ok(
            !malformedReplyHref.includes(`thread=${fixture.middle}`),
            "malformed thread query does not leak partial thread param into reply links"
        );

        const response = await page.goto(`${entryURL}?thread=${fixture.target}`, { waitUntil: "networkidle2" });
        assert.equal(response.status(), 200);
        assert.deepEqual(await commentState(page, fixture.target), {
            wrapperDepth: 1, indicatorDepth: 1, mobileIndent: true, expanded: true,
        }, "opening a thread directly still starts at depth 1");

        function expected(depth) {
            return [depth, depth + 1].map(value => ({
                wrapperDepth: value, indicatorDepth: value, mobileIndent: false, expanded: true,
            }));
        }
        assert.deepEqual({ fromEntry, fromThread, fromMalformedThread }, {
            fromEntry: expected(3), fromThread: expected(2), fromMalformedThread: expected(3),
        }, "expansion preserves the displayed parent and child depths in full, partial, and fallback views");
        console.log("PASS: nested expansion preserves entry-relative and thread-relative depth");
    } finally {
        try {
            if (browser) await browser.close();
        } finally {
            deleteFixture("comment-depth", fixture.user);
        }
    }
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
