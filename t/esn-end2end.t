# t/est-end2end.t
#
# Test ESN system end to end TODO?
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

use Test::More tests => 12;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Protocol;
use LJ::Event;
use LJ::Test qw(memcache_stress temp_user);
use FindBin qw($Bin);

unless ( LJ::is_enabled('esn') ) {
    plan skip_all => "ESN is disabled: set $LJ::DISABLED{esn}=0 to run this test.";
    exit 0;
}

test_esn_flow(
    sub {
        my ( $u1, $u2, $path ) = @_;
        my $subsc = $u1->subscribe(
            event   => "JournalNewEntry",
            method  => "Email",
            journal => $u2,
        );
        ok( $subsc, "got subscription" );

        my $got_email = 0;
        local $LJ::_T_EMAIL_NOTIFICATION = sub {
            my $email = shift;
            $got_email = $email;
        };

        my $entry = $u2->t_post_fake_entry;
        ok( $entry, "made a post" );

        LJ::Event->process_fired_events;

        ok( $got_email, "got the email on path $path" );

        # remove subscription
        ok( $subsc->delete, "Removed subscription" );
    }
);

sub test_esn_flow {
    my $cv = shift;
    my $u1 = temp_user();
    my $u2 = temp_user();
    foreach my $path ( '1-4', '1-2-4', '1-2-3-4' ) {
        if ( $path eq '1-2-4' ) {
            local $LJ::_T_ESN_FORCE_P1_P2 = 1;
            $cv->( $u1, $u2, $path );
        }
        elsif ( $path eq '1-2-3-4' ) {
            local $LJ::_T_ESN_FORCE_P1_P2 = 1;
            local $LJ::_T_ESN_FORCE_P2_P3 = 1;
            $cv->( $u1, $u2, $path );
        }
        else {
            $cv->( $u1, $u2, $path );
        }
        sleep 1;
    }
}

1;

