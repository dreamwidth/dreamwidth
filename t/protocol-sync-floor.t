# t/protocol-sync-floor.t
#
# Test that a first-ever syncitems / getevents (no lastsync) returns entries
# under both strict and permissive MySQL sql_mode.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 22;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Protocol;
use LJ::Test qw( temp_user );

my $STRICT = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,'
    . 'ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

my $u = temp_user();
$u->t_post_fake_entry( subject => "sync floor $_" ) foreach 1 .. 3;

my $do_request = sub {
    my ( $mode, %args ) = @_;
    my $err = 0;
    my $res = LJ::Protocol::do_request( $mode, { ver => 1, username => $u->user, %args },
        \$err, { noauth => 1 } );
    return ( $res, $err );
};

# The protocol reads from the cluster reader; set the mode on every handle it
# might use so the session matches what we're testing.
my $set_mode = sub {
    my ($mode) = @_;
    foreach my $dbh ( LJ::get_cluster_reader($u), LJ::get_cluster_master($u) ) {
        $dbh->do( 'SET SESSION sql_mode = ?', undef, $mode );
        die $dbh->errstr if $dbh->err;
    }
    my ($got) = LJ::get_cluster_reader($u)->selectrow_array('SELECT @@SESSION.sql_mode');
    return $got;
};

foreach my $mode ( $STRICT, '' ) {
    my $label = $mode ? 'strict' : 'empty';
    is( $set_mode->($mode), $mode, "cluster reader session is in $label sql_mode" );

    {
        my ( $res, $err ) = $do_request->('syncitems');
        ok( !$err, "first-ever syncitems succeeds ($label)" ) or diag($err);
        is( $res->{count}, 3, "first-ever syncitems lists every entry ($label)" );
        is( scalar( grep { $_->{item} =~ /^L-/ } @{ $res->{syncitems} || [] } ),
            3, "syncitems items are entries ($label)" );
    }

    {
        my ( $res, $err ) = $do_request->( 'getevents', selecttype => 'syncitems' );
        ok( !$err, "first-ever getevents(syncitems) succeeds ($label)" ) or diag($err);
        is( scalar @{ $res->{events} || [] },
            3, "first-ever getevents(syncitems) returns every entry ($label)" );
    }

    # Some clients store and send back an explicit zero date; treat it the same.
    {
        my ( $res, $err ) = $do_request->( 'syncitems', lastsync => '0000-00-00 00:00:00' );
        ok( !$err, "zero-date syncitems succeeds ($label)" ) or diag($err);
        is( $res->{count}, 3, "zero-date syncitems lists every entry ($label)" );

        ( $res, $err ) = $do_request->(
            'getevents',
            selecttype => 'syncitems',
            lastsync   => '0000-00-00 00:00:00'
        );
        ok( !$err, "zero-date getevents(syncitems) succeeds ($label)" ) or diag($err);
        is( scalar @{ $res->{events} || [] },
            3, "zero-date getevents(syncitems) returns every entry ($label)" );
    }

    # A real lastsync after every entry still returns nothing.
    {
        my ( $res, $err ) = $do_request->( 'syncitems', lastsync => '2999-01-01 00:00:00' );
        is( $res->{count}, 0, "syncitems after the newest entry is empty ($label)" );
    }

    # Clear the getevents loop detector so the second mode starts fresh.
    $u->set_prop( rl_syncitems_getevents_loop => undef );
}
