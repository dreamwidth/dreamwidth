# t/cleaner-links.t
#
# Test HTMLCleaner with links.
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use warnings;

use Test::More tests => 9;

BEGIN { require "$ENV{LJHOME}/cgi-bin/LJ/Directories.pm"; }
use HTMLCleaner;

sub clean {
    my $output = '';
    my $cleaner = HTMLCleaner->new(
        output => sub { $output .= $_[0] },
        valid_stylesheet => sub { $_[0] eq 'http://www.example.com/valid.css' },
    );

    my $input = shift;
    $cleaner->parse( $input );
    $cleaner->eof;
    
    return $output;
}

sub is_cleaned {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $input = shift;
    my $type = shift;
    my $output = clean($input);
    is( $output, '', $type );
}

sub not_cleaned {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $input = shift;
    my $type = shift;
    my $output = clean($input);
    is( $output, $input, $type );
}

not_cleaned(
    '<link rel="alternate" href="http://www.livejournal.com">',
    "html link rel=alternate"
);

not_cleaned(
    '<link rel="shortcut" href="http://www.livejournal.com/favicon.ico">',
    "html link with single valid rel attribute"
);

not_cleaned(
    '<link rel="shortcut icon" href="http://www.livejournal.com/favicon.ico">',
    "html link with two valid rel attributes"
);

not_cleaned(
    '<link>http://example.com/foo.html</link>',
    "rss style link"
);

not_cleaned(
    '<link href="http://example.com/foo.html" />',
    "html/atom link, rel is implied 'alternate' in this form"
);

is_cleaned(
    '<link rel="stylesheet" href="http://www.example.com/bar.css">',
    "html link with disallowed stylesheet href"
);

is_cleaned(
    '<link rel="alternate fox" href="http://www.example.com/bar.css">',
    "html link with one good and one bad rel value"
);

not_cleaned(
    '<link rel="stylesheet" href="http://www.example.com/valid.css">',
    "html link with good stylesheet"
);

is_cleaned(
    '<link rel="script">',
    "html link with script rel, this is not allowed ever",
);
