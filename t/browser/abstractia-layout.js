// t/browser/abstractia-layout.js
//
// Render generated Abstractia stylesheets to test column geometry.
//
// Authors:
//      SAPHID <saphid@users.noreply.github.com>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself.  For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.
//
// Run inside the devcontainer after capturing base and candidate stylesheets
// from journals with identical properties and no custom CSS:
//   node t/browser/abstractia-layout.js BASE.css CANDIDATE.css [SIDEBAR_PERCENT MARGIN_PERCENT BREAKPOINT_PX]
// Defaults: sidebar_width=20, margins_size=5, medium breakpoint=640px.
// Uses bin/dev/screenshot's existing dependencies; never installs or starts anything.
// Includes a real title, native-size archive calendar, and wide entry and comment content.

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const puppeteer = require("/opt/dw-screenshot/node_modules/puppeteer-core");

const [, , baseFile, candidateFile, sidebar = "20", margins = "5", breakpoint = "640"] = process.argv;
assert(baseFile && candidateFile, "supply BASE.css and CANDIDATE.css");
const bp = Number(breakpoint);
assert(Number(sidebar) > 0 && Number(margins) >= 0 && bp >= 480,
    "use feasible sidebar/margin settings and a breakpoint of at least 480px");
const base = fs.readFileSync(baseFile, "utf8");
const candidate = fs.readFileSync(candidateFile, "utf8");
const reset = fs.readFileSync(path.resolve(__dirname, "../../htdocs/stc/reset.css"), "utf8");
// Model declaration rejection only. This does not establish support in an old browser.
const fallback = candidate
    .replace(/[-\w]+\s*:[^;{}]*\bmax\s*\([^;{}]*;/g, "")
    .replace(/@media[^{}]*\bmax\s*\([^{}]*\{/g, "@media not all {");
const fits = Math.ceil(20000 / Number(sidebar));
function stackThreshold(layout, pageKind) {
    const count = layout.startsWith("two-") ? 1 : 2;
    const available = Math.max(1, 97 - 2 * Number(margins) - (layout === "three-columns-sides" ? 1 : 0));
    const percent = Math.max(1, available - count * Number(sidebar));
    const minimum = (pageKind === "archive" ? 35 : 20) * 16;
    return Math.max((count * 200 + minimum) * 100 / available, minimum * 100 / percent);
}
const widths = [...new Set([bp - 1, bp, 640, 768, 800, 889, Math.max(bp, fits), Math.max(bp, 1400),
    ...["two-columns-left", "three-columns-left", "three-columns-sides"].flatMap(layout =>
        ["recent", "archive"].flatMap(kind => {
            const threshold = stackThreshold(layout, kind);
            return [Math.floor(threshold), Math.ceil(threshold) + 1];
        }))])].sort((a, b) => a - b);
const layouts = ["one-column", "two-columns-left", "two-columns-right",
    "three-columns-left", "three-columns-sides", "three-columns-right"];
const html = `<!doctype html><html><head></head><body>
<div id="canvas"><div class="inner">
<div id="header"><div class="inner">Journal title</div></div>
<div id="content"><div class="inner">
<div id="primary"><div class="inner" style="height:600px">
<div class="entry"><div class="header"><h3 class="entry-title">Stress content: long URL, table and preformatted text</h3></div></div>
<table id="native-calendar"><tr><th>Sun</th><th>Mon</th><th>Tue</th><th>Wed</th><th>Thu</th><th>Fri</th><th>Sat</th></tr>
<tr><td>1</td><td>2</td><td>3</td><td>4</td><td>5</td><td>6</td><td>7</td></tr></table>
</div></div>
<div id="secondary"><div class="inner" style="height:120px">Modules</div></div>
<div id="invisible-separator" style="float:left;width:1px"></div>
<div id="tertiary"><div class="inner" style="height:100px">More modules</div></div>
<div id="content-footer"></div></div></div></div>
<div id="footer"><div class="inner"><div class="page-top"><a href="#">Top</a></div></div></div>
</div></body></html>`;
const near = (a, b, why) => assert(Math.abs(a - b) <= 1, `${why}: ${a} versus ${b}`);
function equalBoxes(a, b, why) {
    for (const id of Object.keys(a)) {
        for (const key of Object.keys(a[id])) near(a[id][key], b[id][key], `${why} #${id}.${key}`);
    }
}
function separate(a, b, why) {
    const x = Math.min(a.right, b.right) - Math.max(a.left, b.left);
    const y = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
    assert(x <= 1 || y <= 1, `${why}: overlap ${x}px by ${y}px`);
}

const wideWidths = [640, 768, 800, 889];
// Mirrors Abstractia's entry and comment markup around the author's text. The styled
// image is exempt from imageshrink.css, as are images in tables and styled divs.
function fillWideContent(classes) {
    document.body.className = classes;
    for (const id of ["secondary", "tertiary"]) {
        document.querySelector(`#${id} > .inner`).style.height = "1500px";
    }
    const primary = document.querySelector("#primary > .inner");
    primary.style.height = "auto";
    const userpic = `<div class="userpic"><img alt="" style="width:100px;height:100px"></div>`;
    const wide = `<p><a href="#">https://example.test/${"x".repeat(131)}</a></p>
        <img class="wide" alt="" style="display:block;width:600px;height:80px">
        <pre>${"C".repeat(80)}</pre>`;
    primary.innerHTML = `
<div class="entry-wrapper has-userpic"><div class="entry"><div class="inner">
<div class="header"><div class="inner"><h3 class="entry-title">Wide entry</h3></div></div>
<div><div class="contents"><div class="inner">${userpic}
<div class="entry-content">${"Text beside the userpic. ".repeat(12)}${wide}</div>
</div></div></div></div></div></div>
<div class="comment-wrapper has-userpic"><div class="comment"><div class="inner">
<div class="header"><div class="inner"><h4 class="comment-title">Wide comment</h4></div></div>
<div class="contents"><div class="inner">${userpic}
<div class="comment-content">${"Reply text. ".repeat(12)}${wide}</div>
</div></div></div></div></div>`;
}
function measureWideContent() {
    const rect = (element) => {
        const r = element.getBoundingClientRect();
        return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width };
    };
    const primary = rect(document.querySelector("#primary"));
    const sidebars = ["#secondary", "#tertiary"].map((id) => rect(document.querySelector(id)));
    return [".entry", ".comment"].map((kind) => {
        const box = document.querySelector(`${kind} .contents > .inner`);
        const overflowX = getComputedStyle(box).overflowX;
        const parts = { image: box.querySelector("img.wide"), pre: box.querySelector("pre"),
            link: box.querySelector(".entry-content a, .comment-content a") };
        const outer = rect(box);
        const painted = {};
        for (const [name, element] of Object.entries(parts)) {
            const r = rect(element);
            // Preformatted text paints to its scroll width; a scroll area clips to its box.
            if (name === "pre") r.right = r.left + element.scrollWidth;
            if (overflowX !== "visible") {
                r.left = Math.max(r.left, outer.left);
                r.right = Math.min(r.right, outer.right);
            }
            painted[name] = r;
        }
        box.scrollLeft = box.scrollWidth;
        const end = box.scrollLeft;
        box.scrollLeft = 0;
        return { kind: kind.slice(1), overflowX, primary, sidebars, painted, box: outer,
            image: rect(parts.image), pre: rect(parts.pre), link: rect(parts.link),
            text: rect(box.querySelector(".entry-content, .comment-content")),
            userpic: rect(box.querySelector(".userpic")),
            preScrollWidth: parts.pre.scrollWidth, clientWidth: box.clientWidth,
            scrollWidth: box.scrollWidth, end };
    });
}

// Core2 indents the .dwexpcomment box, outside Abstractia's minimum-width
// comment wrapper. Keep the whole thread reachable without painting on a sidebar.
function fillDeepComments(classes) {
    document.body.className = classes.replace("page-recent", "page-entry");
    document.querySelector("#secondary > .inner").style.height = "1500px";
    document.querySelector("#tertiary > .inner").style.height = "1500px";
    const primary = document.querySelector("#primary > .inner");
    primary.style.height = "auto";
    const comment = (depth) => `<div class="dwexpcomment" style="margin-left:${(depth - 1) * 25}px;margin-top:5px">
<div class="comment-wrapper"><div class="comment"><div class="inner">
<div class="header"><div class="inner"><h4 class="comment-title">Depth ${depth}</h4></div></div>
<div class="contents"><div class="inner"><div class="comment-content">A short readable reply.</div></div></div>
</div></div></div></div>`;
    primary.innerHTML = `<p>Short entry.</p><div id="comments"><div class="inner">
${Array.from({ length: 7 }, (_, i) => `<div class="comment-thread comment-depth-${i + 1}" data-comment-depth="${i + 1}">`).join("")}
${comment(7)}<div class="comment-thread comment-depth-8" data-comment-depth="8">${comment(8)}</div>
${"</div>".repeat(7)}</div></div>`;
}
function measureDeepComments() {
    const rect = (element) => {
        const r = element.getBoundingClientRect();
        return { left: r.left, right: r.right, top: r.top, bottom: r.bottom };
    };
    const comments = document.querySelector("#comments");
    const container = rect(comments);
    const clipping = getComputedStyle(comments).overflowX !== "visible";
    const wrappers = [...document.querySelectorAll(".comment-wrapper")].map((element) => {
        const box = rect(element);
        return { ...box, left: clipping ? Math.max(box.left, container.left) : box.left,
            right: clipping ? Math.min(box.right, container.right) : box.right };
    });
    comments.scrollLeft = comments.scrollWidth;
    const end = comments.scrollLeft;
    const lastAtEnd = rect(document.querySelector(".comment-depth-8 .comment-wrapper"));
    comments.scrollLeft = 0;
    return { container, wrappers, primary: rect(document.querySelector("#primary")),
        sidebars: ["#secondary", "#tertiary"].map(id => rect(document.querySelector(id))),
        scrollWidth: comments.scrollWidth, clientWidth: comments.clientWidth, end, lastAtEnd };
}

(async () => {
    const browser = await puppeteer.launch({
        executablePath: "/usr/bin/google-chrome-stable",
        args: ["--no-sandbox", "--disable-gpu", "--hide-scrollbars"],
    });
    try {
        const page = await browser.newPage();
        await page.setRequestInterception(true);
        page.on("request", (request) => request.abort());
        for (const layout of layouts) {
            for (const pageKind of ["recent", "archive"]) {
            const multiple = layout !== "one-column";
            const count = layout.startsWith("two-") ? "two-columns" : "three-columns";
            const classes = `page-${pageKind} any-column ${layout} ${multiple ? "multiple-columns " + count : ""}`;
            for (const width of widths) {
                await page.setViewport({ width, height: 1000 });
                const measurements = {};
                for (const [label, css] of Object.entries({ base, candidate, fallback })) {
                    await page.setContent(html);
                    await page.evaluate((value) => {
                        document.body.className = value;
                        // Archive pages contain the calendar, rather than entry-title headers.
                        if (document.body.classList.contains("page-archive")) {
                            document.querySelector(".entry").remove();
                        }
                    }, classes);
                    await page.addStyleTag({ content: reset + "\n" + css + "\nbody:not(.page-archive) #native-calendar {display:none}" });
                    measurements[label] = await page.evaluate(() => {
                        const result = {};
                        for (const id of ["header", "primary", "secondary", "tertiary", "footer .page-top"]) {
                            const r = document.querySelector("#" + id).getBoundingClientRect();
                            result[id] = { left: r.left, right: r.right, top: r.top,
                                bottom: r.bottom, width: r.width };
                        }
                        const title = document.querySelector(".entry-title");
                        result.titleClips = title ? title.scrollWidth > title.clientWidth + 1 : false;
                        const calendar = document.querySelector("#native-calendar").getBoundingClientRect();
                        result.calendar = { left: calendar.left, right: calendar.right,
                            top: calendar.top, bottom: calendar.bottom, width: calendar.width };
                        return result;
                    });
                }
                const why = `${pageKind} ${layout} at ${width}px`;
                const threshold = stackThreshold(layout, pageKind);
                const responsive = multiple && layout !== "three-columns-right";
                const stacked = responsive && width <= threshold;
                const before = measurements.base;
                const after = measurements.candidate;
                equalBoxes(measurements.fallback, before, `${why}: fallback`);
                if (!multiple || width < bp || width >= Math.max(fits, threshold) || layout === "three-columns-right") {
                    equalBoxes(after, before, `${why}: unchanged geometry`);
                }
                if (responsive && width >= bp) {
                    assert(!after.titleClips, `${why}: title text must remain visible`);
                    if (pageKind === "archive") {
                        separate(after.calendar, after.secondary, `${why}: calendar/secondary`);
                        separate(after.calendar, after.tertiary, `${why}: calendar/tertiary`);
                    }
                }
                if (stacked && width >= bp) {
                    near(after.primary.left, width * Number(margins) / 100, `${why}: stacked main left`);
                    assert(after.secondary.top >= after.primary.bottom - 1, `${why}: secondary stacks`);
                    assert(after.tertiary.top >= after.secondary.bottom - 1, `${why}: tertiary stacks`);
                }
                if (multiple && width >= bp && !stacked) {
                    const p = after.primary, s = after.secondary, t = after.tertiary;
                    near(s.width, Math.max(200, width * Number(sidebar) / 100), `${why}: sidebar minimum`);
                    separate(p, s, `${why}: primary/secondary`);
                    near(p.top, s.top, `${why}: secondary stays beside entries`);
                    if (count === "three-columns") {
                        separate(p, t, `${why}: primary/tertiary`);
                        separate(s, t, `${why}: secondary/tertiary`);
                        if (layout !== "three-columns-right") {
                            near(p.top, t.top, `${why}: tertiary stays beside entries`);
                        }
                    }
                    if (count === "two-columns") {
                        near(after.header.left, p.left, `${why}: header left`);
                        near(after.header.right, p.right, `${why}: header right`);
                        near(after["footer .page-top"].left, p.left, `${why}: footer left`);
                        near(after["footer .page-top"].width, p.width, `${why}: footer width`);
                    } else if (layout !== "three-columns-right") {
                        near(after["footer .page-top"].left, p.left, `${why}: footer left`);
                    }
                }
                // Sidebars at their minimum leave less room for entries than author content
                // often needs. Entry and comment content must scroll or wrap inside its own
                // box instead of painting over a sidebar or widening the page.
                if (multiple && pageKind === "recent" && width >= bp
                    && wideWidths.includes(width)) {
                    await page.setContent(html);
                    await page.evaluate(fillWideContent, classes);
                    await page.addStyleTag({ content: reset + "\n" + candidate });
                    const wide = await page.evaluate(measureWideContent);
                    for (const item of wide) {
                        const what = `${why}: wide ${item.kind} content`;
                        const tooWide =
                            Math.max(item.image.width, item.preScrollWidth) > item.clientWidth;
                        // Beside a sidebar the reserved column is always narrower than the image.
                        assert(stacked || tooWide,
                            `${what}: stress content must be wider than its column`);
                        for (const part of ["image", "pre", "link"]) {
                            assert(item.painted[part].right <= item.primary.right + 1,
                                `${what}: ${part} paints past the entry column`);
                            for (const sidebar of item.sidebars) {
                                separate(item.painted[part], sidebar, `${what}: ${part}/sidebar`);
                            }
                        }
                        assert(["auto", "scroll"].includes(item.overflowX),
                            `${what}: needs a horizontal scroll area`);
                        if (tooWide) {
                            assert(item.scrollWidth > item.clientWidth && item.end > 0,
                                `${what}: image and code remain reachable by horizontal scrolling`);
                        }
                        assert(item.link.right <= item.box.right + 1, `${what}: long URL wraps`);
                        assert(item.text.left < item.userpic.right
                            && item.text.right > item.userpic.left,
                            `${what}: text still flows around the userpic`);
                    }
                    measurements.wide = wide;
                }
                if (pageKind === "recent" && [bp - 1, ...wideWidths].includes(width)) {
                    const deep = {};
                    for (const [label, css] of Object.entries({ base, candidate })) {
                        await page.setContent(html);
                        await page.evaluate(fillDeepComments, classes);
                        await page.addStyleTag({ content: reset + "\n" + css });
                        deep[label] = await page.evaluate(measureDeepComments);
                    }
                    if (!multiple || width < bp) {
                        assert.deepEqual(deep.candidate, deep.base,
                            `${why}: deep comments retain one-column/mobile behavior`);
                    } else {
                        const item = deep.candidate;
                        for (const wrapper of item.wrappers) {
                            assert(wrapper.right <= item.primary.right + 1,
                                `${why}: deep comment paints past the primary column`);
                            for (const sidebar of item.sidebars) {
                                separate(wrapper, sidebar, `${why}: deep comment/sidebar`);
                            }
                        }
                        if (item.scrollWidth > item.clientWidth + 1) {
                            assert(item.end > 0 && item.lastAtEnd.right <= item.container.right + 1,
                                `${why}: deep comment remains reachable by horizontal scrolling`);
                        }
                    }
                    measurements.deep = deep;
                }
                console.log(JSON.stringify({ pageKind, layout, width, stacked, ...measurements }));
            }
        }
            }
        console.error("Abstractia column geometry and content constraints passed.");
    } finally {
        await browser.close();
    }
})().catch((error) => { console.error(error); process.exitCode = 1; });
