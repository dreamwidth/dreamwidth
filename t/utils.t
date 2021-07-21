# t/utils.t
#
# Test LJ::Utils module
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
#

use strict;
use warnings;

use Test::More tests => 6;

use Scalar::Util;

BEGIN { require "$ENV{LJHOME}/t/lib/ljtestlib.pl"; }
use LJ::Utils;

is( length( LJ::rand_chars(0) ),  0 );
is( length( LJ::rand_chars(1) ),  1 );
is( length( LJ::rand_chars(10) ), 10 );

my $m = LJ::md5_struct("hello");
is( $m->hexdigest, "5d41402abc4b2a76b9719d911017c592" );

my $rand_int = LJ::urandom_int();
ok( Scalar::Util::looks_like_number($rand_int) );

is( length( LJ::urandom( size => 10 ) ), 10 );
