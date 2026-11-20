# t/support-mass-close.t
#
# Tests closing a batch of support requests with points for the last answer.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
use DBI::Profile;
use HTTP::Request::Common;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user with_fake_memcache );
use DW::Controller::Support::ActMulti;
use DW::Request::Standard;

my $dbh = LJ::get_db_writer();
my $catid;
my @requests;
my @responders;

END {
    for my $spid (@requests) {
        $dbh->do( 'DELETE FROM supportlog WHERE spid=?',    undef, $spid );
        $dbh->do( 'DELETE FROM supportpoints WHERE spid=?', undef, $spid );
        $dbh->do( 'DELETE FROM support WHERE spid=?',       undef, $spid );
    }
    for my $userid (@responders) {
        $dbh->do( 'DELETE FROM supportpointsum WHERE userid=?', undef, $userid );
    }
    LJ::Support::delete_cat($catid) if $catid;
}

my $created = time() - 3 * 24 * 60 * 60;

sub request {
    $dbh->do( 'INSERT INTO support (spcatid, state, timecreate) VALUES (?, "open", ?)',
        undef, $catid, $created )
        or die $dbh->errstr;
    push @requests, $dbh->{mysql_insertid};
    return $requests[-1];
}

sub add_response {
    my ( $spid, $userid, $type, $hours ) = @_;
    $dbh->do( 'INSERT INTO supportlog (spid, userid, type, timelogged) VALUES (?, ?, ?, ?)',
        undef, $spid, $userid, $type, $created + $hours * 60 * 60 )
        or die $dbh->errstr;
    return $dbh->{mysql_insertid};
}

with_fake_memcache {
    my $closer = temp_user();
    my ( $first, $second ) = map { $_->userid } temp_user(), temp_user();
    @responders = ( $first, $second );
    my $catkey = 't_' . LJ::rand_chars(15);
    $catid = LJ::Support::define_cat( { catkey => $catkey, basepoints => 2 } );
    $closer->grant_priv( 'supportclose', $catkey );

    my ( $multiple, $repeat, $other, $unanswered, $unmarked ) = map { request() } 1 .. 5;
    add_response( $multiple, $second, 'answer', 1 );
    my $last = add_response( $multiple, $first, 'answer', 12 );
    add_response( $multiple,   $second, 'internal', 18 );
    add_response( $repeat,     $first,  'answer',   1 );
    add_response( $other,      $second, 'answer',   60 );
    add_response( $unanswered, $second, 'screened', 6 );
    add_response( $unmarked,   $first,  'answer',   6 );

    LJ::start_request();
    DW::Request->reset;
    DW::Request::Standard->new( GET 'http://www.dw.test/support/help' );
    LJ::set_remote($closer);
    my $auth = LJ::form_auth(1);

    DW::Request->reset;
    my $return  = "/support/help?state=open&cat=$catkey";
    my $request = DW::Request::Standard->new(
        POST 'http://www.dw.test/support/actmulti',
        Content => [
            'action:closewithpoints' => 1,
            lj_form_auth             => $auth,
            spcatid                  => $catid,
            ret                      => "$return%s",
            ids                      => join( ':', @requests ),
            map { ( "check_$_" => 1 ) } ( $multiple, $repeat, $other, $unanswered )
        ]
    );
    LJ::set_remote($closer);

    my $profile = DBI::Profile->new( Path => [ '!Statement', '!MethodName' ] );
    $dbh->{Profile} = $profile;
    my $result = DW::Controller::Support::ActMulti::actmulti_handler();
    $dbh->{Profile} = undef;

    is( $result, $request->REDIRECT, 'successful batch redirects to the support board' );
    my $refreshes = 0;
    while ( my ( $statement, $methods ) = each %{ $profile->{Data} } ) {
        next unless $statement =~ /^REPLACE INTO supportpointsum\b/;
        $refreshes += $methods->{do}[0];
    }
    is( $refreshes, 1, 'refreshes point totals once for the entire batch' );

    is_deeply(
        $dbh->selectall_arrayref(
            'SELECT state, timeclosed > 0, timemodified = timeclosed FROM support '
                . 'WHERE spcatid=? ORDER BY spid',
            undef,
            $catid
        ),
        [ ( map { [ 'closed', 1, 1 ] } 1 .. 4 ), [ 'open', undef, undef ] ],
        'only marked requests are closed, with closure and modification timestamps'
    );
    is_deeply(
        $dbh->selectall_arrayref(
            'SELECT spid, userid, points FROM supportpoints JOIN support USING (spid) '
                . 'WHERE spcatid=? ORDER BY spid',
            undef,
            $catid
        ),
        [ [ $multiple, $first, 4 ], [ $repeat, $first, 2 ], [ $other, $second, 10 ] ],
        'awards the newest answer per marked request; no points for screened responses'
    );
    is_deeply(
        $dbh->selectall_hashref(
            'SELECT userid, totpoints FROM supportpointsum WHERE userid IN (?, ?)',
            'userid', undef, $first, $second
        ),
        {
            $first  => { userid => $first,  totpoints => 6 },
            $second => { userid => $second, totpoints => 10 }
        },
        'point totals include every award, including multiple awards to one volunteer'
    );
    my $logs = $dbh->selectall_hashref(
        'SELECT spid, message FROM supportlog JOIN support USING (spid) '
            . 'WHERE spcatid=? AND type="internal" AND userid=?',
        'spid', undef, $catid, $closer->userid
    );
    is( scalar keys %$logs, 4, 'logs each closure under the acting volunteer' );
    like(
        $logs->{$multiple}{message},
        qr/granting 4 points .* response #$last\b/,
        'closure log identifies the winning answer and point award'
    );
    unlike( $logs->{$unanswered}{message}, qr/granting/, 'unanswered closure logs no award' );
};

done_testing;
