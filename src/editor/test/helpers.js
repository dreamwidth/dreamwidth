// src/editor/test/helpers.js
//
// Test setup: the editor's import/export code runs against the DOM, so give it
// a jsdom one.
//
// Authors:
//     Mark Smith <mark@qq.is>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself.  For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

import { JSDOM } from "jsdom";

const dom = new JSDOM("<!doctype html><html><body></body></html>");
globalThis.window = dom.window;
globalThis.document = dom.window.document;
// prosemirror-view (pulled in by prosemirror-tables) reads these at load time.
if (!globalThis.navigator) globalThis.navigator = dom.window.navigator;

const { schema } = await import("../src/schema.js");
const { importHTML, exportHTML } = await import("../src/serialize.js");

export { schema, importHTML, exportHTML };

// Load HTML into a document and write it straight back out.
export function roundTrip(html, importOpts, exportOpts) {
    return exportHTML(schema, importHTML(schema, html, importOpts), exportOpts);
}

// Compare markup ignoring whitespace between tags, so a test states what has
// to survive rather than how the serializer lays it out.
export function normalized(html) {
    const tpl = document.createElement("template");
    tpl.innerHTML = html;
    return tpl.innerHTML.replace(/>\s+</g, "><").trim();
}
