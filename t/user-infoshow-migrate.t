# t/user-infoshow-migrate.t
#
# Test display of user location/birthday/etc with migration.
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

use Test::More tests => 156;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test qw(temp_user memcache_stress);

$LJ::DISABLED{infoshow_migrate} = 0;

sub new_temp_user {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $u = temp_user();

    subtest "created new temp user" => sub {
        plan tests => 4;

        ok( LJ::isu($u), 'temp user created' );

        # force it to Y, since we're testing migration here
        $u->update_self( { allow_infoshow => 'Y' } );
        $u->clear_prop("opt_showlocation");
        $u->clear_prop("opt_showbday");

        is( $u->{'allow_infoshow'}, 'Y', 'allow_infoshow set to Y' );
        ok( !defined $u->{'opt_showbday'},     'opt_showbday not set' );
        ok( !defined $u->{'opt_showlocation'}, 'opt_showlocation not set' );
    };

    return $u;
}

sub run_tests {
    foreach my $getter (
        sub { $_[0]->prop('opt_showbday') },
        sub { $_[0]->prop('opt_showlocation') },
        sub { $_[0]->opt_showbday },
        sub { $_[0]->opt_showlocation }
        )
    {
        foreach my $mode (qw(default off)) {
            my $u = new_temp_user();
            if ( $mode eq 'off' ) {
                my $uid = $u->{userid};
                $u->update_self( { allow_infoshow => 'N' } );
                is( $u->{allow_infoshow}, 'N', 'allow_infoshow set to N' );

                my $temp_var = $getter->($u);
                is( $temp_var,                'N', "prop value after migration: 'N'" );
                is( $u->{'allow_infoshow'},   ' ', 'lazy migrate: allow_infoshow set to SPACE' );
                is( $u->{'opt_showbday'},     'N', 'lazy_migrate: opt_showbday set to N' );
                is( $u->{'opt_showlocation'}, 'N', 'lazy_migrate: opt_showlocation set to N' );
            }
            else {
                my $temp_var = $getter->($u);
                ok( defined $temp_var, "prop value after migration: defined" );
                is( $u->{'allow_infoshow'},   ' ',   'lazy migrate: allow_infoshow set to SPACE' );
                is( $u->{'opt_showbday'},     undef, 'lazy_migrate: opt_showbday unset' );
                is( $u->opt_showbday,         'D',   "lazy_migrate: opt_showbday returned as D" );
                is( $u->{'opt_showlocation'}, undef, 'lazy_migrate: opt_showlocation unset' );
                is( $u->opt_showlocation,     'Y',   "lazy_migrate: opt_showlocation set as Y" );
            }
        }
    }

}

memcache_stress {
    run_tests;
}
