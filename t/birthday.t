# t/birthday.t
#
# Test birthday display options.
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

use Test::More tests => 186;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user memcache_stress);

sub run_tests {
    {
        my $rv = eval { LJ::User::can_show_bday(undef) };
        like( $@, qr/invalid user/, "can_show_bday: Undef is not a user" );
    }

    {
        my $u  = temp_user();
        my $rv = eval { $u->can_show_bday };
        ok( !$@, "can_show_bday: Called on valid user object" );
    }

    {
        my $u  = temp_user();
        my $rv = eval { $u->can_show_bday };
        if ( $rv == 0 ) {
            ok( !$rv, "can_show_bday: opt_showbday is not set" );
        }
    }

    foreach my $val (qw(D F)) {
        my $u = temp_user();
        $u->set_prop( 'opt_showbday', $val );
        my $rv = eval { $u->can_show_bday };
        ok( $rv, "can_show_bday: opt_showbday is set to $val" );
    }

    foreach my $val (qw(N Y)) {
        my $u = temp_user();
        $u->set_prop( 'opt_showbday', $val );
        my $rv = eval { $u->can_show_bday };
        if ( $rv == 0 ) {
            ok( !$rv, "can_show_bday: opt_showbday is set to $val" );
        }
    }

    {
        my $rv = eval { LJ::User::can_show_bday_year(undef) };
        like( $@, qr/invalid user/, "can_show_bday_year: Undef is not a user" );
    }

    {
        my $u  = temp_user();
        my $rv = eval { $u->can_show_bday_year };
        ok( !$@, "can_show_bday_year: Called on valid user object" );
    }

    {
        my $u  = temp_user();
        my $rv = eval { $u->can_show_bday_year };
        if ( $rv == 0 ) {
            ok( !$rv, "can_show_bday_year: opt_showbday is not set" );
        }
    }

    foreach my $val (qw(F Y)) {
        my $u = temp_user();
        $u->set_prop( 'opt_showbday', $val );
        my $rv = eval { $u->can_show_bday_year };
        ok( $rv, "can_show_bday_year: opt_showbday is set to $val" );
    }

    foreach my $val (qw(N D)) {
        my $u = temp_user();
        $u->set_prop( 'opt_showbday', $val );
        my $rv = eval { $u->can_show_bday_year };
        ok( !$rv, "can_show_bday_year: opt_showbday is set to $val" );
    }

    {
        my $rv = eval { LJ::User::can_show_full_bday(undef) };
        like( $@, qr/invalid user/, "can_show_full_bday: Undef is not a user" );
    }

    {
        my $u  = temp_user();
        my $rv = eval { $u->can_show_full_bday };
        ok( !$@, "can_show_full_bday: Called on valid user object" );
    }

    {
        my $u  = temp_user();
        my $rv = eval { $u->can_show_full_bday };
        if ( $rv == 0 ) {
            ok( !$rv, "can_show_full_bday: opt_showbday is not set" );
        }
    }

    {
        my $u = temp_user();
        $u->set_prop( 'opt_showbday', 'F' );
        my $rv = eval { $u->can_show_full_bday };
        ok( $rv, "can_show_full_bday:  opt_showbday is set to F" );
    }

    foreach my $val (qw(D N Y)) {
        my $u = temp_user();
        $u->set_prop( 'opt_showbday', $val );
        my $rv = eval { $u->can_show_full_bday };
        ok( !$rv, "can_show_full_bday: opt_showbday is set to $val" );
    }

    {
        my $rv = eval { LJ::User::bday_string(undef) };
        like( $@, qr/invalid user/, "bday_string: Undef is not a user" );
    }

    {
        my $u  = temp_user();
        my $rv = eval { $u->bday_string };
        ok( !$@, "bday_string: Called on valid user object" );
    }

    my @props = ( '', 'D', 'F', 'N', 'Y' );
    foreach my $year ( '0000', '1979' ) {
        foreach my $month ( '00', '01' ) {
            foreach my $day ( '00', '31' ) {
                foreach my $val (@props) {
                    my $u = temp_user();
                    $u->{'bdate'} = $year . '-' . $month . '-' . $day;
                    $u->set_prop( 'opt_showbday', $val );
                    my $rv = eval { $u->bday_string };
                    if ( $val eq 'Y' ) {
                        my $isok = 0;
                        if ( $year eq '1979' && $rv eq $year ) {
                            $isok = 1;
                        }
                        elsif ( $year eq '0000' && $rv eq '' ) {
                            $isok = 1;
                        }
                        ok( $isok, "bday_string 'Y' ($val [$u->{'bdate'}]):  $rv" );
                    }
                    elsif ( $val eq 'D' ) {
                        my $isok = 0;
                        if ( $month eq '01' && $day eq '31' && $rv eq '01-31' ) {
                            $isok = 1;
                        }
                        elsif ( ( $month eq '00' || $day eq '00' ) && $rv eq '' ) {
                            $isok = 1;
                        }
                        ok( $isok, "bday_string 'D' ($val [$u->{'bdate'}]):  $rv" );
                    }
                    elsif ( $val eq 'F' ) {
                        my $isok = 0;
                        if (   $month eq '01'
                            && $day eq '31'
                            && $year eq '1979'
                            && $rv eq '1979-01-31' )
                        {
                            $isok = 1;
                        }
                        elsif ( $month eq '00' || $day eq '00' ) {
                            if ( $year eq '0000' && $rv eq '' ) {
                                $isok = 1;
                            }
                            elsif ( $year eq '1979' && $rv eq '1979' ) {
                                $isok = 1;
                            }
                        }
                        elsif ( $month eq '01' && $day eq '31' ) {
                            if ( $year eq '0000' && $rv eq '01-31' ) {
                                $isok = 1;
                            }
                        }
                        ok( $isok, "bday_string 'F' ($val [$u->{'bdate'}]):  $rv" );
                    }
                    elsif ( $val eq 'N' ) {
                        my $isok = 0;
                        if ( $rv eq '' ) {
                            $isok = 1;
                        }
                        ok( $isok, "bday_string 'N' and empty ($val [$u->{'bdate'}]):  $rv" );
                    }
                    else {
                        my $isok = 0;
                        if ( $year eq '0000' ) {
                            if ( $month eq '01' && $day eq '31' && $rv eq '01-31' ) {
                                $isok = 1;
                            }
                            elsif ( $rv eq '' ) {
                                $isok = 1;
                            }
                        }
                        elsif ( $year eq '1979' ) {
                            if ( $month eq '01' && $day eq '31' && $rv eq '01-31' ) {
                                $isok = 1;
                            }
                            elsif ( ( $month eq '00' || $day eq '00' ) && $rv eq '' ) {
                                $isok = 1;
                            }
                        }
                        ok( $isok, "bday_string '' and empty ($val [$u->{'bdate'}]):  $rv" );
                    }
                }
            }
        }
    }
}

memcache_stress {
    run_tests();
};

1;

