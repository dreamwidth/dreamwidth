# t/cleaner-rte0-convert.t
#
# The retired rte0 format has no cleaner rules of its own: the cleaner treats
# it as casual HTML (automatic line breaks, auto-links, @mentions). Opening an
# rte0 entry for editing converts it to explicit HTML (rte1), and the entry
# must read the same afterwards. The contract is that the cleaned output of a
# body is identical before (cleaned as rte0) and after conversion (cleaned as
# rte1).
#
# Authors:
#      Mark Smith <mark@qq.is>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::CleanHTML;
use LJ::Test qw( temp_user );

my $alice = temp_user();
my $bob   = temp_user();
my ( $ua, $ub ) = ( $alice->user, $bob->user );
my ( $at_a, $at_b ) = ( '@' . $ua, '@' . $ub );

my @bodies = (
    [ 'plain lines',         "one\ntwo\n\nthree" ],
    [ 'crlf lines',          "one\r\ntwo\r\n" ],
    [ 'a url',               "see http://example.com/page?x=1&y=2 for more" ],
    [ 'a url ending a line', "go to http://example.com/\nthen back" ],
    [ 'a url in a link',     qq{<a href="http://example.com/">http://example.com/</a> and text} ],
    [ 'an @mention',         "hi $at_a and\n$at_b!" ],
    [ 'a mention first',     "$at_a opens the entry" ],
    [ 'an escaped mention',  "not a mention: \\$at_a, but $at_b is" ],
    [ 'an email address',    "write to someone\@example.com\nplease" ],
    [ 'a mention in a link', qq{<a href="http://example.com/">$at_a</a> text} ],
    [ 'a mention in code',   "<code>$at_a</code>\n$at_b" ],
    [ 'a mention in a pre',  "<pre>$at_a\nline</pre>\n$at_b" ],
    [ 'a user tag',          qq{hi <lj user="$ua">\nand <user name="$ub">} ],
    [ 'markup and text',     "<p>first</p>\nloose line\n<b>bold</b> tail\n" ],
    [ 'a pre block',         "before\n<pre>a\nb  c\nhttp://example.com/</pre>\nafter" ],
    [ 'a cut', qq{top\n<lj-cut text="more">hidden\nlines http://example.com/</lj-cut>\nbottom} ],
    [
        'a table with text and a url in a cell',
qq{<table>\n<tr>\n<td>cell one\nhttp://example.com/x</td>\n<td>cell $at_a</td>\n</tr>\n</table>\nafter}
    ],
    [ 'a table with nested markup', qq{<table><tr><td><p>a</p>\nb</td></tr></table>\n\nz} ],
    [ 'a poll tag',                 "before\n<poll-123>\nafter text\nmore text" ],
    [ 'an lj-embed placeholder',    qq{before\n<lj-embed id="1" />\nafter\nhttp://example.com/} ],
    [
        'an embed with newlines',
        qq{x\n<site-embed id="1"><iframe src="http://example.com/"\n></iframe></site-embed>\ny}
    ],
    [ 'a stray less-than', "1 < 2 and 3 > 2\nok" ],
    [ 'entities',          "fish &amp; chips\n&lt;b&gt;" ],
    [
        'a twitter blockquote',
        qq{<blockquote class="twitter-tweet">$at_a says\n</blockquote>\n$at_b}
    ],
    [ 'raw code', "<raw-code>$at_a\nline</raw-code>\n$at_b" ],

    # Where the cleaner's idea of what is open differs from a plain reading of
    # the tags: it closes things implicitly, or never closes them.
    [ 'code closed by an outer end tag', "<div><code>inside</div> outside $at_a\nnext" ],
    [
        'a self-closed anchor',
        qq{<a href="http://example.com/" /> text http://example.com/x $at_a\nnext}
    ],
    [ 'an unclosed pre', "<pre>a\nb http://example.com/ $at_a\n" ],
    [
        'an anchor closed by a block',
qq{<a href="http://example.com/">link text<div>block $at_a\nmore http://example.com/y</div></a> after}
    ],
    [ 'mis-nested tags', "<b><i>x</b></i> $at_a\nline" ],
    [
        'nested tables',
"<table><tr><td><table><tr><td>a\nb</td></tr></table>c\nd http://example.com/</td></tr></table>\ne"
    ],
    [
        'an unclosed table cell',
        "<table><tr><td>a\nb http://example.com/\n<tr><td>c</table>\nafter\n$at_a"
    ],
    [ 'an unclosed textarea',  "<textarea>a\nb $at_a" ],
    [ 'a code span left open', "<code>one\n$at_a\ntwo" ],

    # Text the cleaner skips, with the same words as text it shows: each token
    # has to get its own context.
    [
        'an ignored title duplicating body text',
        "<title>same\nwords $at_a</title>same\nwords $at_a"
    ],
    [
        'a script duplicating body text',
        "<script>same\nwords</script>same\nwords http://example.com/"
    ],
    [ 'repeated text in and out of a pre', "<pre>x\ny</pre>x\ny <pre>x\ny</pre>x\ny" ],
);

plan tests => scalar @bodies;

# The one allowed difference: the old path wrote an auto-linked URL's "&" into
# the href as-is, while cleaning explicit markup writes it as "&amp;". Both mean
# the same URL, so compare hrefs with the ampersands normalized.
sub same_href {
    my ($html) = @_;
    $html =~ s{(href="[^"]*")}{ my $h = $1; $h =~ s/&amp;/&/g; $h }ge;
    return $html;
}

foreach my $case (@bodies) {
    my ( $name, $body ) = @$case;

    my $before = $body;
    LJ::CleanHTML::clean_event( \$before, { editor => 'rte0' } );

    my $explicit = LJ::CleanHTML::casual_to_explicit($body);
    my $after    = $explicit;
    LJ::CleanHTML::clean_event( \$after, { editor => 'rte1' } );

    is( same_href($after), same_href($before), "$name: renders the same once converted" )
        or diag("explicit source: $explicit");
}
