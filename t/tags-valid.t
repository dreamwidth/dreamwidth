# t/tags-valid.t
#
# Test LJ::Tags::is_valid_tagstring
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

use Test::More tests => 14;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Tags;

my $validated;

$validated = [];
ok(   LJ::Tags::is_valid_tagstring( "tag 1, tag 2", $validated ), "simple case" );
is_deeply( $validated, [ "tag 1", "tag 2" ], "simple case" );

note( "underscores" );
$validated = [];
ok( ! LJ::Tags::is_valid_tagstring( "tag 1, _tag 2, tag 3", $validated ), "has leading underscore" );
is_deeply( $validated, [ "tag 1" ], "has leading underscore (cut short)" );

$validated = [];
ok(   LJ::Tags::is_valid_tagstring( "tag 1, tag 2_, tag 3", $validated ), "has trailing underscore" );
is_deeply( $validated, [ "tag 1", "tag 2_", "tag 3" ], "has trailing underscore" );

$validated = [];
ok(   LJ::Tags::is_valid_tagstring( "tag 1, tag_2, tag 3", $validated ), "has internal underscore" );
is_deeply( $validated, [ "tag 1", "tag_2", "tag 3" ], "has internal underscore" );

note( "extra whitespace" );
$validated = [];
ok(   LJ::Tags::is_valid_tagstring( "tag 1 , tag 2  , tag 3   ", $validated ), "trailing spaces" );
is_deeply( $validated, [ "tag 1", "tag 2", "tag 3" ], "trailing spaces" );

$validated = [];
ok(   LJ::Tags::is_valid_tagstring( " tag 1,  tag 2,   tag 3", $validated ), "leading spaces" );
is_deeply( $validated, [ "tag 1", "tag 2", "tag 3" ], "leading spaces" );


note( "spaces + truncation" );
$validated = [];
ok(   LJ::Tags::is_valid_tagstring( "x" x ( LJ::CMAX_KEYWORD - 1 ) . " yyy" , $validated ), "truncated right at a trailing space" );
is_deeply( $validated, [ "x" x ( LJ::CMAX_KEYWORD - 1 ) ], "truncated right at a trailing space; didn't save the trailing space" );
