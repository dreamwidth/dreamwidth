# t/cleaner-autolink.t
#
# Test auto-linking of plain-text URLs in comments, entries, and
# LJ::auto_linkify, especially URLs that end in a closing paren.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 17;

BEGIN { require "$ENV{LJHOME}/t/lib/ljtestlib.pl"; }
use LJ::CleanHTML;
use LJ::Web;

my $wiki = 'https://en.wikipedia.org/wiki/Function_(mathematics)';

sub link_to {
    my ($url) = @_;
    return qq{<a href="$url">$url</a>};
}

my $comment = sub {
    my ($text) = @_;
    LJ::CleanHTML::clean_comment( \$text, {} );
    chomp $text;
    return $text;
};

my $entry = sub {
    my ($text) = @_;
    LJ::CleanHTML::clean_event( \$text, {} );
    chomp $text;
    return $text;
};

note("comments");
is( $comment->($wiki), link_to($wiki), "URL ending in a balanced paren keeps its closing paren" );
is(
    $comment->("(see $wiki)"),
    '(see ' . link_to($wiki) . ')',
    "only the paren that the URL opened is linked, not the sentence's paren"
);
is( $comment->("$wiki."), link_to($wiki) . '.', "trailing period is not linked" );
is(
    $comment->('(see https://example.com/page)'),
    '(see ' . link_to('https://example.com/page') . ')',
    "unmatched closing paren after a URL is not linked"
);
is(
    $comment->('https://example.com/a_(b)_c)'),
    link_to('https://example.com/a_(b)_c') . ')',
    "unmatched closing paren after balanced parens is not linked"
);
is(
    $comment->("&quot;$wiki&quot;"),
    '&quot;' . link_to($wiki) . '&quot;',
    "escaped quote still ends a URL with parens"
);
my ( $one, $two ) = ( 'https://example.com/(1)', 'https://example.com/2' );
is(
    $comment->("a $one b $two)"),
    'a ' . link_to($one) . ' b ' . link_to($two) . ')',
    "several URLs in one comment are each linked correctly"
);

note("entries");
is( $entry->($wiki), link_to($wiki), "URL ending in a balanced paren keeps its closing paren" );

note("LJ::auto_linkify");
is( LJ::auto_linkify($wiki), "<a href='$wiki'>$wiki</a>", "balanced closing paren is linked" );
is(
    LJ::auto_linkify('(see https://example.com/page)'),
    "(see <a href='https://example.com/page'>https://example.com/page</a>)",
    "unmatched closing paren is not linked"
);
is( LJ::auto_linkify('https://.)'), 'https://.)', "no link is made to a bare scheme" );
is( LJ::auto_linkify(undef),        undef,        "undef input returns undef" );

my $nested = 'https://example.com/f((x))';
is(
    LJ::auto_linkify($nested),
    "<a href='$nested'>$nested</a>",
    "nested balanced parens are linked"
);
my $extra = 'https://example.com/f(x).))&quot;';
is(
    LJ::auto_linkify($extra),
    "<a href='https://example.com/f(x)'>https://example.com/f(x)</a>.))&quot;",
    "punctuation, excess parens and an entity remain in their original order"
);
my $long_tail = ')' x 16384;
is(
    LJ::auto_linkify( 'https://example.com/a' . $long_tail ),
    "<a href='https://example.com/a'>https://example.com/a</a>" . $long_tail,
    "a long run of excess closing parens stays outside the link"
);

is(
    $comment->('https://ex.com/a)()'),
    link_to('https://ex.com/a') . ')()',
    "dropping an opening paren also unmatches an earlier closing paren"
);
is(
    LJ::auto_linkify('(https://example.com/page)(:)'),
    "(<a href='https://example.com/page'>https://example.com/page</a>)(:)",
    "punctuation between trailing parens does not leave an unmatched linked paren"
);
