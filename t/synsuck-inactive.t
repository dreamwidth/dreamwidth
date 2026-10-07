# t/synsuck-inactive.t
#
# Test that LJ::SynSuck backs off on feeds with no active readers, that a new
# watch wakes the feed, and that the metrics describing this are emitted.
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

use Test::More tests => 42;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use HTTP::Response;
use LJ::SynSuck;
use LJ::Test qw(temp_user temp_feed);

# capture DW::Stats::increment calls instead of sending them anywhere
my @stats;
{
    no warnings 'redefine';
    *DW::Stats::increment = sub {
        my ( $metric, $by, $tags ) = @_;
        push @stats, join( ' ', $metric, @{ $tags || [] } );
    };
}

sub stats_seen {
    return scalar grep { $_ eq $_[0] } @stats;
}

sub set_active {
    my ( $u, $when ) = @_;
    $u->do(
        "REPLACE INTO clustertrack2 SET userid=?, timeactive=?, clusterid=?, "
            . "accountlevel=0, journaltype=?",
        undef, $u->id, $when, $u->clusterid, $u->journaltype
    );
    LJ::MemCache::set( [ $u->id, "timeactive:" . $u->id ], $when, 86400 );
}

sub watch {
    my ( $reader, $feed ) = @_;
    $reader->add_edge( $feed, watch => { nonotify => 1 } ) or die "unable to watch";
}

sub minutes_until_check {
    my $feed = shift;
    return LJ::get_db_writer()
        ->selectrow_array(
        "SELECT TIMESTAMPDIFF(MINUTE, NOW(), checknext) FROM syndicated WHERE userid=?",
        undef, $feed->id );
}

my $now  = time();
my $idle = $now - 400 * 86400;

is( $LJ::SYNSUCK_INACTIVE_READER_DAYS, 180,         "default reader age is 180 days" );
is( $LJ::SYNSUCK_INACTIVE_INTERVAL,    7 * 24 * 60, "default inactive interval is a week" );
is( $LJ::SYNSUCK_ACTIVE_READER_PROBES, 50,          "default probe cap is 50" );

my $week = $LJ::SYNSUCK_INACTIVE_INTERVAL;

note("no watchers");
{
    my $feed = temp_feed();
    is( LJ::SynSuck::readership($feed), 'no_watchers', "no watchers classified" );
    is( LJ::SynSuck::reader_interval( $feed, 60 ), $week, "no watchers gets inactive interval" );
    ok( stats_seen('dw.synsuck.readership class:no_watchers'), "readership metric emitted" );
    ok( stats_seen('dw.synsuck.interval bucket:inactive'),     "inactive interval metric emitted" );
}

note("idle watchers");
{
    my $feed = temp_feed();
    foreach ( 1 .. 2 ) {
        my $r = temp_user();
        set_active( $r, $idle );
        watch( $r, $feed );
    }
    is( LJ::SynSuck::readership($feed), 'all_inactive', "idle watchers classified" );
    is( LJ::SynSuck::reader_interval( $feed, 60 ), $week, "idle watchers get inactive interval" );
}

note("one active watcher");
{
    @stats = ();
    my $feed = temp_feed();
    my ( $old, $new ) = ( temp_user(), temp_user() );
    set_active( $old, $idle );
    set_active( $new, $now - 86400 );
    watch( $old, $feed );
    watch( $new, $feed );
    is( LJ::SynSuck::readership($feed), 'active', "active watcher found" );
    is( LJ::SynSuck::reader_interval( $feed, 60 ), 60, "normal interval kept" );
    ok( stats_seen('dw.synsuck.readership class:active'), "active readership metric emitted" );
    ok( stats_seen('dw.synsuck.interval bucket:normal'),  "normal interval metric emitted" );
}

note("watcher without a clustertrack2 row falls back to account creation time");
{
    my $feed = temp_feed();
    my $r    = temp_user();    # created just now, never logged in
    watch( $r, $feed );
    is( LJ::SynSuck::readership($feed), 'active', "new account counts as active" );
}

note("old account with no clustertrack2 row is inactive");
{
    my $feed = temp_feed();
    my $r    = temp_user();
    LJ::get_db_writer()->do( "UPDATE userusage SET timecreate=FROM_UNIXTIME(?) WHERE userid=?",
        undef, $idle, $r->id );
    LJ::MemCache::delete( [ $r->id, "tc:" . $r->id ] );
    delete $r->{_cache_timecreate};
    LJ::memcache_kill( $r->id, 'userid' );
    watch( $r, $feed );
    is( LJ::SynSuck::readership($feed), 'all_inactive', "old never-active account doesn't count" );
}

note("deleted and suspended watchers are ignored");
{
    my $feed = temp_feed();
    my ( $gone, $susp ) = ( temp_user(), temp_user() );
    foreach ( $gone, $susp ) {
        set_active( $_, $now );
        watch( $_, $feed );
    }
    $gone->set_deleted;
    $susp->set_suspended( LJ::load_user('system'), "test" );
    LJ::memcache_kill( $gone->id, 'userid' );
    LJ::memcache_kill( $susp->id, 'userid' );
    is( LJ::SynSuck::readership( LJ::load_userid( $feed->id ) ),
        'all_inactive', "recently active but deleted/suspended watchers don't count" );
}

note("probe cap");
{
    local $LJ::SYNSUCK_ACTIVE_READER_PROBES = 2;
    my $feed    = temp_feed();
    my @readers = map { temp_user() } 1 .. 4;
    foreach my $r (@readers) { set_active( $r, $idle ); watch( $r, $feed ); }
    is( LJ::SynSuck::readership($feed), 'probe_cap', "gives up after the cap and assumes active" );
    @stats = ();
    is( LJ::SynSuck::reader_interval( $feed, 60 ), 60, "probe cap keeps the normal interval" );
    ok( stats_seen('dw.synsuck.readership class:probe_cap'), "probe_cap metric emitted" );

    # with no more watchers than the cap, we can be sure
    my $small = temp_feed();
    my @two   = map { temp_user() } 1 .. 2;
    foreach my $r (@two) { set_active( $r, $idle ); watch( $r, $small ); }
    is( LJ::SynSuck::readership($small), 'all_inactive', "list within the cap is conclusive" );
}

note("configured interval is honoured");
{
    local $LJ::SYNSUCK_INACTIVE_INTERVAL = 1440;
    my $feed = temp_feed();
    is( LJ::SynSuck::reader_interval( $feed, 60 ), 1440, "interval can be put back to a day" );
}

note("new watch wakes the feed");
{
    @stats = ();
    my $feed = temp_feed();
    LJ::get_db_writer()->do(
        "UPDATE syndicated SET checknext=DATE_ADD(NOW(), INTERVAL 7 DAY), failcount=3 "
            . "WHERE userid=?",
        undef, $feed->id
    );
    ok( minutes_until_check($feed) > 1000, "feed scheduled far out before the watch" );

    my $r = temp_user();
    watch( $r, $feed );
    ok( minutes_until_check($feed) <= 0, "watch pulled checknext back to now" );
    is(
        LJ::get_db_writer()->selectrow_array(
            "SELECT failcount FROM syndicated WHERE userid=?", undef, $feed->id
        ),
        0,
        "failcount cleared"
    );
    ok( stats_seen('dw.synsuck.wake reason:watch'), "wake metric emitted" );

    # watching again (e.g. editing the colours) isn't a new reader
    @stats = ();
    LJ::get_db_writer()
        ->do( "UPDATE syndicated SET checknext=DATE_ADD(NOW(), INTERVAL 7 DAY) WHERE userid=?",
        undef, $feed->id );
    watch( $r, $feed );
    ok( minutes_until_check($feed) > 1000,           "re-watching doesn't wake the feed" );
    ok( !stats_seen('dw.synsuck.wake reason:watch'), "no wake metric for re-watch" );
}

note("not-modified response on a feed with no readers");
{
    @stats = ();

    package FakeUA;
    sub new { bless {}, shift }
    sub agent   { }
    sub request { HTTP::Response->new(304) }

    package main;

    no warnings 'redefine';
    local *LJ::get_useragent = sub { FakeUA->new };

    my $feed = temp_feed();
    my $dbh  = LJ::get_db_writer();
    my $urow = $dbh->selectrow_hashref(
        "SELECT u.user, s.userid, s.synurl, s.lastmod, s.etag, s.numreaders, s.checknext "
            . "FROM user u, syndicated s WHERE u.userid=s.userid AND s.userid=?",
        undef, $feed->id
    );
    LJ::SynSuck::get_content($urow);

    my $mins = minutes_until_check($feed);
    ok(
        $mins >= $week - 1 && $mins <= $week * 1.1 + 1,
        "304 path uses the inactive interval ($mins)"
    );
    ok( stats_seen('dw.synsuck.check outcome:notmodified'), "check outcome metric emitted" );
}

note("fetched feed with no readers");
{
    @stats = ();
    my $rss = q{<?xml version="1.0"?><rss version="2.0"><channel><title>t</title>
        <link>http://example.com/</link><description>d</description>
        <item><title>one</title><link>http://example.com/1</link><guid>g1</guid>
        <description>hi</description></item></channel></rss>};

    my $feed = temp_feed();
    my $dbh  = LJ::get_db_writer();
    my $urow = $dbh->selectrow_hashref(
        "SELECT u.user, s.userid, s.synurl, s.lastmod, s.etag, s.numreaders, s.checknext "
            . "FROM user u, syndicated s WHERE u.userid=s.userid AND s.userid=?",
        undef, $feed->id
    );
    my $res = HTTP::Response->new(200);
    $res->header( 'Content-Type' => 'application/rss+xml' );
    ok( LJ::SynSuck::process_content( $urow, [ $res, $rss ] ), "feed processed" );

    my $mins = minutes_until_check($feed);
    ok( $mins >= $week - 1 && $mins <= $week + 1, "fetch path uses the inactive interval ($mins)" );
    ok( stats_seen('dw.synsuck.check outcome:ok'), "check outcome metric emitted" );
}

note("failure paths");
{
    my $dbh       = LJ::get_db_writer();
    my $failcount = sub {
        $dbh->selectrow_array( "SELECT failcount FROM syndicated WHERE userid=?", undef,
            $_[0]->id );
    };

    # nobody reading: a failing feed waits out the inactive interval, but still counts failures
    @stats = ();
    my $dead = temp_feed();
    LJ::SynSuck::delay( $dead->id, 180, "parseerror" );
    my $mins = minutes_until_check($dead);
    ok( $mins >= $week - 1,
        "failing feed with no readers waits at least the inactive interval ($mins)" );
    is( $failcount->($dead), 1, "failcount still incremented" );
    ok(
        stats_seen('dw.synsuck.readership class:no_watchers'),
        "readership metric emitted on failure path"
    );
    ok(
        stats_seen('dw.synsuck.interval bucket:inactive'),
        "inactive bucket counted on failure path"
    );
    ok( stats_seen('dw.synsuck.check outcome:parseerror'), "outcome tag unchanged" );

    # someone reading: normal backoff (3h * 2 for the first failure, plus jitter)
    @stats = ();
    my $live = temp_feed();
    my $r    = temp_user();
    set_active( $r, $now );
    watch( $r, $live );
    LJ::SynSuck::delay( $live->id, 180, "parseerror" );
    $mins = minutes_until_check($live);
    ok( $mins >= 359 && $mins <= 400,
        "failing feed with an active reader keeps normal backoff ($mins)" );
    is( $failcount->($live), 1, "failcount incremented" );
    ok( stats_seen('dw.synsuck.interval bucket:normal'), "normal bucket counted on failure path" );

    # transient conditions on our side don't consult readership at all
    @stats = ();
    my $nodb = temp_feed();
    LJ::SynSuck::delay( $nodb->id, 15, "nodb", undef, { backoff => 'hold' } );
    ok( minutes_until_check($nodb) < 60,                 "nodb keeps its short delay" );
    ok( !( grep { /^dw\.synsuck\.readership/ } @stats ), "no readership lookup for nodb" );
}
