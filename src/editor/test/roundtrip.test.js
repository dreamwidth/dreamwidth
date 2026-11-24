// Load -> export round trips of existing entry HTML. Whatever the poster
// didn't touch has to come back out: the editor is only safe to open old
// entries in if it never silently drops markup it has no button for.
//
// (Style attributes below are written the way jsdom serializes them -- with a
// space and trailing semicolon -- because it reformats them when set from
// script. Real browsers keep the text as written.)
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.

import test from "node:test";
import assert from "node:assert/strict";
import { DOMSerializer } from "prosemirror-model";
import { schema, importHTML, exportHTML, roundTrip, normalized } from "./helpers.js";

function assertSurvives(html, message) {
    assert.equal(normalized(roundTrip(html)), normalized(html), message);
}

test("plain formatting survives", () => {
    assertSurvives("<p>one <strong>two</strong> <em>three</em></p><p>four</p>");
    assertSurvives('<p>a <a href="http://example.com/" title="t">link</a></p>');
    assertSurvives("<h2>Title</h2><ul><li>a</li><li>b</li></ul><blockquote><p>q</p></blockquote>");
});

test("span, font, and small keep their attributes", () => {
    assertSurvives('<p>x <span style="color: red;">red</span> y</p>');
    assertSurvives('<p><font color="#ff0000" size="3">old school</font></p>');
    assertSurvives("<p>fine <small>print</small> and <big>large</big></p>");
});

test("nested inline wrappers survive", () => {
    assertSurvives('<p><span class="a"><span class="b">deep</span></span></p>');
    assertSurvives('<p><span style="color: red;"><strong>both</strong></span></p>');
});

test("div and center blocks survive, with and without block children", () => {
    assertSurvives('<div style="text-align: center;">centered text</div>');
    assertSurvives("<center>old center</center>");
    assertSurvives('<div class="outer"><p>one</p><p>two</p></div>');
    assertSurvives('<div id="x"><div class="inner">nested</div></div>');
});

test("a div mixing text and blocks is kept verbatim", () => {
    assertSurvives("<div>loose text<p>and a paragraph</p></div>");
});

test("class, style, id, and align on modeled elements survive", () => {
    assertSurvives('<p class="note" style="margin: 0px;" id="p1" align="right">text</p>');
    assertSurvives('<h3 class="t">head</h3>');
    assertSurvives('<ul class="fancy"><li class="first">a</li></ul>');
    assertSurvives('<ol type="a" start="3"><li>c</li></ol>');
    assertSurvives('<p><img src="http://example.com/a.png" alt="a" style="float: left;" border="0"></p>');
    assertSurvives('<p><a href="http://example.com/" target="_blank" class="out">x</a></p>');
});

test("anchors without an href survive, empty or not", () => {
    assertSurvives('<p><a name="top"></a>Heading</p>');
    assertSurvives('<p><a name="mid">anchored text</a></p>');
    assertSurvives('<p>text <span id="marker"></span> more</p>');
});

test("a modeled tag that carries attributes keeps them", () => {
    assertSurvives('<p><b style="color: red;">bold red</b></p>');
});

test("polls, embeds, and tables the editor can't model are kept as raw blocks", () => {
    assertSurvives("<table><caption>c</caption><tbody><tr><td>cell</td></tr></tbody></table>");
    assertSurvives('<poll name="p" id="poll1"><poll-question type="radio"><poll-item>a</poll-item></poll-question></poll>');
    assertSurvives('<iframe src="http://example.com/v"></iframe>');
});

test("elements the schema has no model for are kept", () => {
    assertSurvives("<dl><dt>term</dt><dd>def</dd></dl>");
    assertSurvives("<p>x<wbr>y</p>");
    assertSurvives('<p>see <abbr title="Hypertext">HTML</abbr></p>');
});

test("preformatted text with markup inside is kept", () => {
    assertSurvives("<pre><code>plain\n  indented</code></pre>");
    const rich = '<pre>a <b>bold</b> word</pre>';
    assert.equal(normalized(roundTrip(rich)), normalized(rich));
});

test("user tags survive in text and inside preserved chunks", () => {
    assert.equal(
        normalized(roundTrip('<p>hi <user name="alice"> and <lj user="bob"></p>')),
        normalized('<p>hi <user name="alice"> and <user name="bob"></p>')
    );

    // Inside a preserved chunk the original spelling comes back exactly.
    const table =
        '<table><caption>c</caption><tbody><tr><td><user name="carol"> <lj comm="club"></td></tr></tbody></table>';
    const out = roundTrip(table);
    assert.match(out, /<user name="carol">/);
    assert.match(out, /<lj comm="club">/);
    assert.doesNotMatch(out, /dw-user|data-dw/);
});

test("a stray </user> inside a raw chunk is not stripped", () => {
    const html = "<dl><dt>&lt;/user&gt; text</dt></dl>";
    assert.match(roundTrip(html), /&lt;\/user&gt; text/);
});

test("event handler attributes survive in the stored markup", () => {
    // The live editor omits them (so opening an entry can't run script), but
    // the stored HTML is the poster's and is cleaned by the server.
    assertSurvives('<p onclick="x()">text</p>');
});

test("loose top-level text and breaks are kept", () => {
    const out = roundTrip("first line<br>second line<br><br>third");
    assert.match(out, /first line<br>second line<br><br>third/);
});

test("lists with nested lists and cut tags survive", () => {
    assertSurvives("<ul><li>a<ul><li>b</li></ul></li></ul>");
    assertSurvives('<cut text="more"><p>hidden</p></cut>');
});

test("an unedited document with nothing in it exports as nothing", () => {
    assert.equal(roundTrip(""), "");
    assert.equal(roundTrip("<p></p>"), "");
});

test("the live view omits event handlers but keeps style and class", () => {
    const doc = importHTML(schema, '<p onclick="x()" class="k" style="color: red;">t</p>');
    const dom = schema.nodes.paragraph.spec.toDOM(doc.firstChild);
    assert.equal(dom[1].onclick, undefined);
    assert.equal(dom[1].class, "k");
    assert.equal(dom[1].style, "color: red;");
    // ...while export includes it.
    assert.match(exportHTML(schema, doc), /onclick="x\(\)"/);
});

test("a styled span inside <strong> stays inside it", () => {
    assertSurvives('<p><strong>bold <span style="font-weight: normal;">plain</span> bold</strong></p>');
    assertSurvives('<p><em><font color="red">x</font></em></p>');
    assertSurvives('<p><a href="http://example.com/"><span class="c">linked</span></a></p>');
});

test("a styled span around <strong> stays outside it", () => {
    assertSurvives('<p><span style="font-weight: normal;"><strong>bold</strong></span></p>');
});

test("an element wedged between modeled marks is kept as it was", () => {
    assertSurvives('<p><strong><span class="w"><em>both</em></span></strong></p>');
});

test("an imported javascript: link or src is not put on the live editor DOM", () => {
    const doc = importHTML(
        schema,
        '<p><a href="java\nscript:alert(1)" target="_blank">x</a> <img src="javascript:alert(2)" alt="i"></p>'
    );

    // What the live view builds from the document:
    const live = document.createElement("div");
    live.appendChild(
        DOMSerializer.fromSchema(schema).serializeFragment(doc.content, { document })
    );
    assert.doesNotMatch(live.innerHTML, /javascript/i);
    assert.match(live.innerHTML, /target="_blank"/);

    // ...while what's stored keeps the poster's markup exactly.
    assert.match(exportHTML(schema, doc), /href="java\nscript:alert\(1\)"/);
    assert.match(exportHTML(schema, doc), /src="javascript:alert\(2\)"/);
});

test("ordinary and relative URLs are still shown in the live editor", () => {
    const doc = importHTML(schema, '<p><a href="/local">a</a> <a href="mailto:a@b.c">m</a> <img src="http://example.com/i.png"></p>');
    const live = document.createElement("div");
    live.appendChild(DOMSerializer.fromSchema(schema).serializeFragment(doc.content, { document }));
    assert.match(live.innerHTML, /href="\/local"/);
    assert.match(live.innerHTML, /href="mailto:a@b\.c"/);
    assert.match(live.innerHTML, /src="http:\/\/example\.com\/i\.png"/);
});

test("nested identical generic elements are not merged into one", () => {
    // Two 2em spans, one inside the other, are 4em; merged they'd be 2em.
    assertSurvives('<p><strong><span style="font-size: 2em;">a <span style="font-size: 2em;">b</span></span></strong></p>');
    assertSurvives('<p><span class="x">a <span class="x">b</span></span></p>');

    // Different attributes aren't equal, so they stay editable.
    const out = roundTrip('<p><span class="x">a <span class="y">b</span></span></p>');
    assert.equal(normalized(out), normalized('<p><span class="x">a <span class="y">b</span></span></p>'));
});

test("nested equal generic elements are detected whatever the attribute order", () => {
    // Same two attributes, written in a different order: still equal marks.
    assertSurvives('<p><span class="x" style="color: red;">a <span style="color: red;" class="x">b</span></span></p>');
});
