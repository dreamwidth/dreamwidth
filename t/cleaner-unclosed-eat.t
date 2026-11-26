# t/cleaner-unclosed-eat.t
#
# The cleaner skips the contents of some elements (object, iframe, title, ...).
# When one is never closed it drops only the opening tag, and it has to do that
# in linear time: this runs on every entry and comment, and a post made of
# thousands of unclosed openers must not be a way to tie up a web process.
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

use Test::More tests => 5;
use Time::HiRes qw( time );

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::CleanHTML;

sub cleaned {
    my ($text) = @_;
    LJ::CleanHTML::clean_event( \$text, { editor => 'html_raw0' } );
    return $text;
}

foreach my $tag (qw( object applet )) {
    my $count = 8000;
    my $start = time;
    my $out   = cleaned( ( "<$tag>" x $count ) . "tail text" );
    my $took  = time - $start;
    like( $out, qr/tail text/, "$count unclosed <$tag> openers: the text after them renders" );
    cmp_ok( $took, '<', 2, "...in linear time (${\ sprintf '%.2f', $took}s)" );
}

# Matched ones still skip their contents, wherever they sit among unmatched ones.
my $out = cleaned('<object>never closed<object>gone</object>after');
like( $out, qr/after/, 'a closed object inside an unclosed one still ends where it closes' );
