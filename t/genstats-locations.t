#!/usr/bin/perl
#
# t/genstats-locations.t
#
# Test the country and US state counts that the genstats maintenance task
# collects for the /stats page.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 6;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use File::Temp qw(tempdir);

use LJ::Stats;
use LJ::Test qw(temp_user);

our %maint;
require "$ENV{LJHOME}/bin/maint/stats.pl";

# genstats registers its handlers, runs every job and then writes
# htdocs/stats/stats.txt. Only register the handlers, so the test reads the
# counts without rewriting the site-wide stats tables or the text file.
{
    no warnings 'redefine';
    local *LJ::Stats::run_stats = sub { 1 };
    local $LJ::HTDOCS           = tempdir( CLEANUP => 1 );
    mkdir "$LJ::HTDOCS/stats" or die "mkdir: $!";
    open my $log, '>', \my $output or die;
    my $stdout = select $log;
    $maint{genstats}->();
    select $stdout;
}

my $active   = temp_user();
my $cid      = $active->clusterid;
my $inactive = temp_user( cluster => $cid );
my $moved    = temp_user( cluster => $cid );

# clustertrack2 has a row for accounts that have been active. A row naming a
# different cluster is stale (bin/ljumover.pl deletes those), so the stats
# skip that account's rows on this cluster.
sub set_activity {
    my ( $u, $clusterid ) = @_;
    $u->do( "DELETE FROM clustertrack2 WHERE userid=?", undef, $u->id );
    $u->do(
        "INSERT INTO clustertrack2 SET userid=?, timeactive=UNIX_TIMESTAMP(), clusterid=?, "
            . "accountlevel=0, journaltype=?",
        undef, $u->id, $clusterid, $u->journaltype
    ) if defined $clusterid;
    die $u->errstr if $u->err;
}

set_activity( $active,   $cid );
set_activity( $inactive, undef );
set_activity( $moved,    $cid + 1 );

my $state = 'T' . LJ::rand_chars(8);

sub location_counts {
    my $getter    = sub { LJ::Stats::get_db( "dbcr", $cid ) };
    my $countries = $LJ::Stats::INFO{countries}->{handler}->( $getter, $cid );
    my $states    = $LJ::Stats::INFO{states}->{handler}->( $getter, $cid );
    return ( $countries->{US} // 0, $states->{$state} // 0 );
}

my ($us_before) = location_counts();

$active->set_prop( { country => 'US', state => $state } );
my ( $us, $in_state ) = location_counts();
is( $us - $us_before, 1, 'country count includes an active account' );
is( $in_state,        1, 'state count includes an active account' );

$inactive->set_prop( { country => 'US', state => $state } );
( $us, $in_state ) = location_counts();
is( $us - $us_before, 2, 'country count includes an account with no activity row' );
is( $in_state,        2, 'state count includes an account with no activity row' );

$moved->set_prop( { country => 'US', state => $state } );
( $us, $in_state ) = location_counts();
is( $us - $us_before, 2, 'country count skips an account recorded on another cluster' );
is( $in_state,        2, 'state count skips an account recorded on another cluster' );

# temp_user cleanup does not remove clustered rows.
foreach my $u ( $active, $inactive, $moved ) {
    foreach my $table (qw(clustertrack2 userproplite2)) {
        $u->do( "DELETE FROM $table WHERE userid=?", undef, $u->id );
    }
}
