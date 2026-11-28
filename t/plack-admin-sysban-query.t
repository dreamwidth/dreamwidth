#!/usr/bin/perl
# t/plack-admin-sysban-query.t
#
# Regression test for the /admin/sysban query listing: several active bans on
# the same value must each get their own row, newest first, so that a full page
# still offers the button for older bans and paging reaches every ban.
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
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Sysban;
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

# ?as= impersonation is dev-only; form auth binds to a fixed uniq below.
local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'sysbanQueryTest';

# A ban type no other test uses keeps the listing to the bans made here.
my $what = 't3544_' . LJ::rand_chars(8);
my $dbh  = LJ::get_db_writer();

# Insert directly with a past bandate: the listing skips bans dated NOW().
my $add_ban = sub {
    my ( $value, %opts ) = @_;
    my $status   = $opts{status} || 'active';
    my $banuntil = $opts{expired} ? 'NOW() - INTERVAL 1 HOUR' : 'NULL';
    $dbh->do(
        "INSERT INTO sysban (status, what, value, note, bandate, banuntil) "
            . "VALUES (?, ?, ?, ?, NOW() - INTERVAL 1 DAY, $banuntil)",
        undef, $status, $what, $value, "note for $value"
    );
    die $dbh->errstr if $dbh->err;
    return $dbh->{mysql_insertid};
};

# Bans that are not active must stay out of the listing and the page count.
$add_ban->( 'dup-one', expired => 1 );
$add_ban->( 'dup-one', status  => 'expired' );

# 21 active bans over only three values: one more than a page of 20.
my @values       = ( 'dup-one', 'dup-two', 'dup<i>three</i>' );
my @banids       = map { $add_ban->( $values[ $_ % 3 ] ) } 0 .. 20;
my @newest_first = reverse @banids;

my $ids = sub {
    [ map { $_->{banid} } @_ ]
};

my $all = LJ::Sysban::list_full_by_type($what);
is_deeply( $ids->(@$all), \@newest_first, 'unpaged list keeps every ban, newest first' );

my $page1 = LJ::Sysban::list_full_by_type( $what, 20, 0 );
my $page2 = LJ::Sysban::list_full_by_type( $what, 20, 20 );
is( scalar @$page1, 20, 'first page is full despite repeated values' );
is_deeply( $ids->( @$page1, @$page2 ), \@newest_first, 'pages together list every ban once' );
is_deeply(
    $page1->[0],
    {
        banid  => $banids[-1],
        value  => $values[2],
        expire => 0,
        note   => "note for $values[2]",
    },
    'each row carries its own ban details'
);

my $admin = temp_user();
$admin->grant_priv( 'sysban', $what );

# Mint a form-auth token for the admin and the fixed uniq, which is what the
# app recomputes for the ?as=<admin> request.
LJ::set_remote($admin);
delete $LJ::REQ_GLOBAL{form_auth_chal};
my $form_auth = LJ::form_auth(1);
LJ::set_remote(undef);

test_psgi $app, sub {
    my $cb = shift;

    my $query = sub {
        my ($skip) = @_;
        my $res = $cb->(
            POST "http://localhost/admin/sysban?as=" . $admin->user,
            Content => [
                lj_form_auth => $form_auth,
                query        => 'Query',
                bantype      => $what,
                skip         => $skip,
            ],
        );
        is( $res->code, 200, "query with skip=$skip renders" );
        my @rows = $res->content =~ /name="banid" value="(\d+)"/g;
        return ( $res->content, \@rows );
    };

    my ( $html, $rows ) = $query->(0);
    is_deeply( $rows, [ @newest_first[ 0 .. 19 ] ], 'first page shows 20 rows, newest first' );
    like( $html, qr/name="skip" value="20"/, 'first page offers the older bans' );
    unlike( $html, qr/<i>three<\/i>/, 'ban values are escaped' );

    ( $html, $rows ) = $query->(20);
    is_deeply( $rows, [ $newest_first[20] ], 'second page shows the remaining ban' );
    like( $html, qr/name="skip" value="0"/, 'second page links back to newer bans' );
    unlike( $html, qr/name="skip" value="40"/, 'second page offers no further page' );
};

$dbh->do( "DELETE FROM sysban WHERE what = ?",     undef, $what );
$dbh->do( "DELETE FROM priv_map WHERE userid = ?", undef, $admin->id );

done_testing();
