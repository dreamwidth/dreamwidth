// Switching an entry between plain formats and the rich editor must neither
// lose line breaks nor change what the server will render.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.

import test from "node:test";
import assert from "node:assert/strict";
import { roundTrip } from "./helpers.js";
import { rawBlockFromText, flattenNewlines } from "../src/serialize.js";

const casual = { links: true, mentions: true, sites: ["livejournal.com"] };

test("casual newlines become explicit line breaks", () => {
    assert.match(roundTrip("one\ntwo\n\nthree", { casual }), /one<br>two<br><br>three/);
});

test("newlines inside <pre> are left alone when converting", () => {
    assert.match(roundTrip("<pre>a\nb</pre>", { casual }), /a\nb/);
});

test("raw chunks keep their newlines when converting", () => {
    const html = "<table><tbody>\n<tr><td>x</td></tr>\n</tbody></table>";
    assert.match(roundTrip(html, { casual }), /<tbody>\n<tr>/);
});

test("casual HTML's auto-links and @mentions become explicit markup", () => {
    const out = roundTrip("see http://example.com/x and @alice, not a@b.com", { casual });
    assert.match(out, /<a href="http:\/\/example\.com\/x">http:\/\/example\.com\/x<\/a>/);
    assert.match(out, /<user name="alice">/);
    assert.match(out, /a@b\.com/);
});

test("external @user.site mentions convert only for known sites", () => {
    assert.match(roundTrip("@bob.livejournal.com hi", { casual }), /<user name="bob" site="livejournal.com">/);
    assert.doesNotMatch(roundTrip("@bob.nowhere hi", { casual }), /<user/);
});

test("markdown conversion keeps line breaks and mentions but does not link URLs", () => {
    const out = roundTrip("a\nb http://example.com @carol", {
        casual: { links: false, mentions: true, sites: [] },
    });
    assert.match(out, /a<br>b http:\/\/example\.com <user name="carol">/);
});

test("raw HTML needs no conversion: newlines are only whitespace", () => {
    assert.doesNotMatch(roundTrip("<p>one\ntwo</p>"), /<br/);
});

test("flattening for casual HTML removes source newlines except in <pre>", () => {
    const html = "<p>a</p>\n\n<p>b</p>\n<pre>x\ny</pre>\n<table>\n<tr>\n</tr></table>";
    assert.equal(flattenNewlines(html), "<p>a</p> <p>b</p> <pre>x\ny</pre> <table> <tr> </tr></table>");
});

test("export for casual HTML emits no newlines for the server to break on", () => {
    const html = "<p>a</p><p>b</p><pre>keep\nme</pre>";
    const out = roundTrip(html, {}, { flatten: true });
    assert.equal(out, "<p>a</p><p>b</p><pre><code>keep\nme</code></pre>");
});

test("pasted poll and embed code is recognized as a block", () => {
    assert.ok(rawBlockFromText('  <poll name="x" id="poll1"><poll-question type="text"> q </poll-question></poll>\n'));
    assert.ok(rawBlockFromText('<iframe src="http://example.com/v"></iframe>'));
    assert.ok(rawBlockFromText('<embed src="http://example.com/v.swf">'));
    assert.equal(rawBlockFromText("just <poll> talk"), null);
    assert.equal(rawBlockFromText("<poll>never closed"), null);
});

test("a bare <embed> is accepted as pasted block markup, unchanged", () => {
    assert.equal(rawBlockFromText('<embed src="http://example.com/v.swf">'), '<embed src="http://example.com/v.swf">');
});

test("raw chunks come back exactly as they were, including embed-like text", () => {
    // The server accepts a bare <embed>, so nothing is rewritten on export;
    // text that merely mentions one inside a raw-text element stays literal.
    const chunks = [
        '<embed src="http://example.com/v.swf">',
        '<xmp>example <embed> tag</xmp>',
        '<iframe src="http://example.com/">fallback <embed> text</iframe>',
        '<script>var s = "<embed src=x>";</script>',
        '<embed title="a > b" src="x">',
    ];
    chunks.forEach((chunk) => {
        const out = roundTrip("<p>a</p>" + chunk + "<p>b</p>");
        assert.ok(out.includes(chunk), "kept: " + chunk + " in " + out);
    });
});

test("server-converted source for an unclosed iframe keeps its text through the editor", () => {
    // Fixture: LJ::CleanHTML::casual_to_explicit("before\nx <iframe src=\"http://e.com/\">after\nthe iframe")
    // omits the opener the cleaner discards and writes the recovered text as
    // ordinary text, so nothing in it can hide the rest of the entry.
    const fixture = "before<br />x after<br />the iframe";
    const out = roundTrip(fixture);
    assert.match(out, /after<br>the iframe/);
    assert.doesNotMatch(out, /iframe>/);
});

test("server-converted source for an unclosed script/style keeps its text through the editor", () => {
    // Fixture: LJ::CleanHTML::casual_to_explicit("before\n<script>tail\ntext") and the
    // same for <style>: the opener that was never closed is left out, so no
    // </script> can be added around the text when the editor saves it.
    const out = roundTrip("before<br />tail<br />text");
    assert.match(out, /tail<br>text/);
    assert.doesNotMatch(out, /script|style/);
});
