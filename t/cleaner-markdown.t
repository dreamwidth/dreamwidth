# t/cleaner-markdown.t
#
# Test LJ::CleanHTML with Markdown text.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2017-2018 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 6;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::CleanHTML;

my $lju_sys = LJ::ljuser("system");
my $url     = 'https://medium.com/@username/title-of-page';

my $as_markdown = sub { return "!markdown\n$_[0]" };

my $clean = sub {
    my ($text) = @_;
    $text = $as_markdown->($text);
    LJ::CleanHTML::clean_event( \$text, { wordlength => 80 } );
    chomp $text;
    return $text;
};

# plain text user tag
is( $clean->('@system'), "<p>$lju_sys</p>", "user tag in plain text converted" );

# escaped plain text user tag
is( $clean->('\@system'), '<p>@system</p>',
    "escaped user tag in plain text not converted, backslash removed" );

# plain text user tag with escape character escaped
is( $clean->('\\\@system'),
    "<p>\\$lju_sys</p>", "user tag in plain text converted when escape character is escaped" );

# plain URL containing user tag
# (Markdown conversion sets preformatted flag, so this won't linkify)
is( $clean->($url), "<p>$url</p>", "user tag in URL not converted" );

# linked URL containing user tag
is(
    $clean->("[link from \@system]($url)"),
    qq{<p><a href="$url">link from $lju_sys</a></p>},
    "user tag in href not converted, but user tag in link text converted []"
);

# same as standard HTML
is(
    $clean->(qq{<a href="$url">link from \@system</a>}),
    qq{<p><a href="$url">link from $lju_sys</a></p>},
    "user tag in href not converted, but user tag in link text converted <>"
);
