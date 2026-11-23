// Load -> export round trips of existing entry HTML. Whatever the poster
// didn't touch has to come back out: the editor is only safe to open old
// entries in if it never silently drops markup it has no button for.
//
// (Style attributes below are written the way jsdom serializes them -- with a
// space and trailing semicolon -- because it reformats them when set from
// script. Real browsers keep the text as written.)

import test from "node:test";
import assert from "node:assert/strict";
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

test("tables, polls, and embeds are kept as raw blocks", () => {
    assertSurvives("<table><tbody><tr><td>cell</td></tr></tbody></table>");
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

    // Inside a table the original spelling comes back exactly.
    const table = '<table><tbody><tr><td><user name="carol"> <lj comm="club"></td></tr></tbody></table>';
    const out = roundTrip(table);
    assert.match(out, /<user name="carol">/);
    assert.match(out, /<lj comm="club">/);
    assert.doesNotMatch(out, /dw-user|data-dw/);
});

test("a stray </user> inside a raw chunk is not stripped", () => {
    const html = "<table><tbody><tr><td>&lt;/user&gt; text</td></tr></tbody></table>";
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
