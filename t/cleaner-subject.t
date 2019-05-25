# t/cleaner-subject.t
#
# Test to TODO
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

use Test::More 'no_plan';    # tests => TODO;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::CleanHTML;
use HTMLCleaner;

my $lju_sys = LJ::ljuser("system");

my $all = sub {
    my $raw = shift;
    LJ::CleanHTML::clean_subject_all( \$raw );
    return $raw;
};

is(
    $all->(
"<span class='ljuser' lj:user='burr86' style='white-space: nowrap;'><a href=''><img src='http://www.henry.lj/img/userinfo.gif' alt='[info]' width='17' height='17' style='vertical-align: bottom; border: 0;' /></a><a href='http://www.henry.lj/userinfo.bml?user=burr86'><b>burr86</b></a></span> kicks butt"
    ),
    "burr86 kicks butt",
    "only text"
);

is( $all->("This is a <b>test</b>"), "This is a test", "only text" );

