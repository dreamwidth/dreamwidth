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
// This isolated fixture tests the core2 container structure, not entry content fit.

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
const fallback = candidate.replace(/[-\w]+\s*:[^;{}]*\bmax\s*\([^;{}]*;/g, "");
const fits = Math.ceil(20000 / Number(sidebar));
const widths = [...new Set([bp - 1, bp, Math.max(bp, 800), Math.max(bp, fits), Math.max(bp, 1400)])];
const layouts = ["one-column", "two-columns-left", "two-columns-right",
    "three-columns-left", "three-columns-sides", "three-columns-right"];
const html = `<!doctype html><html><head></head><body>
<div id="canvas"><div class="inner">
<div id="header"><div class="inner">Journal title</div></div>
<div id="content"><div class="inner">
<div id="primary"><div class="inner" style="height:600px">Entry</div></div>
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
            const multiple = layout !== "one-column";
            const count = layout.startsWith("two-") ? "two-columns" : "three-columns";
            const classes = `page-recent any-column ${layout} ${multiple ? "multiple-columns " + count : ""}`;
            for (const width of widths) {
                await page.setViewport({ width, height: 1000 });
                const measurements = {};
                for (const [label, css] of Object.entries({ base, candidate, fallback })) {
                    await page.setContent(html);
                    await page.evaluate((value) => { document.body.className = value; }, classes);
                    await page.addStyleTag({ content: reset + "\n" + css });
                    measurements[label] = await page.evaluate(() => {
                        const result = {};
                        for (const id of ["header", "primary", "secondary", "tertiary", "footer .page-top"]) {
                            const r = document.querySelector("#" + id).getBoundingClientRect();
                            result[id] = { left: r.left, right: r.right, top: r.top,
                                bottom: r.bottom, width: r.width };
                        }
                        return result;
                    });
                }
                const why = `${layout} at ${width}px`;
                const before = measurements.base;
                const after = measurements.candidate;
                equalBoxes(measurements.fallback, before, `${why}: fallback`);
                if (!multiple || width < bp || width >= fits || layout === "three-columns-right") {
                    equalBoxes(after, before, `${why}: unchanged geometry`);
                }
                if (multiple && width >= bp) {
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
                console.log(JSON.stringify({ layout, width, ...measurements }));
            }
        }
        console.error("Abstractia column geometry passed.");
    } finally {
        await browser.close();
    }
})().catch((error) => { console.error(error); process.exitCode = 1; });
