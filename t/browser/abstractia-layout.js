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
// Includes a real title and native-size archive calendar; arbitrary entry content can still overflow.

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
const widths = [...new Set([bp - 1, bp, 640, 800, Math.max(bp, fits), Math.max(bp, 1400),
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
                console.log(JSON.stringify({ pageKind, layout, width, stacked, ...measurements }));
            }
        }
            }
        console.error("Abstractia column geometry and content constraints passed.");
    } finally {
        await browser.close();
    }
})().catch((error) => { console.error(error); process.exitCode = 1; });
