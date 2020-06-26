# t/clean-event-embed.t
#
# Test LJ::CleanHTML::clean_event.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#      Mark Smith <mark@dreamwidth.org>
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use v5.10;
use strict;
use warnings;

use Test::More tests => 1;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::CleanHTML;
use HTMLCleaner;

# Cleaning <embed> tags within LJ::CleanHTML::clean_event pulls in LJ::Hooks
# which ultimately pulls in ljlib.pl.
#
# Separated out into its own file so that the rest of cleaner-event.t can be
# made independent of ljlib.pl

my $orig_post;
my $clean_post;

my $clean = sub {
    my $opts = shift;

    LJ::CleanHTML::clean_event( \$orig_post, $opts );
};

# embed tags

note("<object> and <embed> tags");
$orig_post =
qq{<object width="640" height="385"><param name="movie" value="http://www.example.com/video"></param><param name="allowFullScreen" value="true"></param><param name="allowscriptaccess" value="always"></param><embed src="http://www.example.com/video" type="application/x-shockwave-flash" allowscriptaccess="always" allowfullscreen="true" width="640" height="385"></embed></object>};
$clean_post = qq{};
$clean->();
is( $orig_post, $clean_post, "<object> and <embed> tags" );
