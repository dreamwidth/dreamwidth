# check the atom feeds that we generate

use strict;
use Test::More tests => 4;

use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Test qw( temp_user );

require 'ljfeed.pl';
use LJ::ParseFeed;

my $u = temp_user();
my $remote = $u;
my $r = DW::Request::Standard->new(
            HTTP::Request->new( GET => $u->journal_base . "/data/atom" ) );


note( "Empty feed" );
{
    my $feed = LJ::ParseFeed::parse_feed(
                LJ::Feed::make_feed( $r, $u, $remote, { pathextra => "/atom" } ),
                "atom" );
    is_deeply( $feed, [], "Empty, but parseable, feed" );
}

{
    note( "Posted entry: entire feed" );
    my $e1 = $u->t_post_fake_entry( subject => "test post in feed (subject)", event => "test post in feed (body)" );
    my $e2 = $u->t_post_fake_entry;

    my $feed = LJ::ParseFeed::parse_feed(
                LJ::Feed::make_feed( $r, $u, $remote, { pathextra => "/atom" } ),
                "atom" );

    my $userid = $u->userid;
    my $e1id = $e1->ditemid;

    my $feed_entryid = delete $feed->[1]->{id};
    delete $feed->[0]->{id};
    like( $feed_entryid, qr/tag:$LJ::DOMAIN,\d{4}-\d{2}-\d{2}:$userid:$e1id/, "Feed entry id" );

    is_deeply( $feed, [{
        link    => $e2->url,
        subject => $e2->subject_raw,
        text    => $e2->event_raw,
        time    => substr( $e2->eventtime_mysql, 0, -3 ),
    }, {
        link    => $e1->url,
        subject => $e1->subject_raw,
        text    => $e1->event_raw,
        time    => substr( $e1->eventtime_mysql, 0, -3 ),
    }], "Check entries from feed" );


    note( "Posted entry: individual item" );
    my $e2id = $e2->ditemid;
    $r = DW::Request::Standard->new(
            HTTP::Request->new( GET => $u->journal_base . "/data/atom?itemid=$e2id" ) );

    $feed = LJ::ParseFeed::parse_feed(
            LJ::Feed::make_feed( $r, $u, $remote, { pathextra => "/atom" } ),
            "atom" );
    delete $feed->[0]->{id};
    is_deeply( $feed->[0], {
        link    => $e2->url,
        subject => $e2->subject_raw,
        text    => $e2->event_raw,
        time    => substr( $e2->eventtime_mysql, 0, -3 ),
    }, "Check individual entry from feed" );
}
