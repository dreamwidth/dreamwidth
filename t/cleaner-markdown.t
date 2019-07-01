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

my $clean = sub {
    my ($text) = @_;
    LJ::CleanHTML::clean_event( \$text, { wordlength => 80, editor => 'markdown' } );
    chomp $text;
    return $text;
};

# plain text user tag
is( $clean->('@system'), "<p>$lju_sys</p>", "user tag in plain text converted" );

# escaped plain text user tag
is( $clean->('\@system'), '<p>@system</p>',
    "escaped user tag in plain text not converted, backslash removed" );

# don't convert in html
is(
    $clean->('<pre>\@system</pre>'),
    '<pre>\@system</pre>', "user tag in plain text converted when escape character is escaped"
);

# plain URL containing user tag
is(
    $clean->($url),
    '<p>https://medium.com/@username/title-of-page</p>',
    'user tag in URL not converted'
);

# linked URL containing user tag
is(
    $clean->("[link from \@system]($url)"),
    qq{<p><a href="$url">link from $lju_sys</a></p>},
    "user tag in href not converted, but user tag in link text converted []"
);

# same as standard HTML, we don't apply markdown to HTML
is(
    $clean->(qq{<a href="$url">link from \@system</a>}),
    qq{<a href="$url">link from \@system</a>},
    "content is unconverted"
);
