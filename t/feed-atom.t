# t/feed-atom.t
#
# Test the atom feeds that we generate.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 10;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user );

use LJ::Feed;
use LJ::ParseFeed;

my $u      = temp_user();
my $remote = $u;
my $r = DW::Request::Standard->new( HTTP::Request->new( GET => $u->journal_base . "/data/atom" ) );
my $site_ns = lc $LJ::SITENAMEABBREV;

sub event_with_commentimage {
    my $e = $_[0];
    return $e->event_raw . "<br /><br />" . $e->comment_imgtag . " comments";
}

note("Empty feed");
{
    my ( $feed, $error ) =
        LJ::ParseFeed::parse_feed( LJ::Feed::make_feed( $r, $u, $remote, { pathextra => "/atom" } ),
        "atom" );
    is( $feed->{link}, $u->journal_base . "/" );
    is( $feed->{type}, "atom" );
    is_deeply( $feed->{items}, [], "Empty, but parseable, feed" );
}

my $e1 = $u->t_post_fake_entry(
    subject => "test post in feed (subject)",
    event   => "test post in feed (body)"
);
my $e2 = $u->t_post_fake_entry;
{
    note("Posted entry: entire feed");
    my $feed_xml = LJ::Feed::make_feed( $r, $u, $remote, { pathextra => "/atom" } );

    my $parser = new XML::Parser( Style => 'Objects' );
    my $parsed = $parser->parse($feed_xml);
    $parsed = $parsed->[0];
    delete $parsed->{Kids};
    is_deeply(
        $parsed,
        {
            'xmlns'          => "http://www.w3.org/2005/Atom",
            "xmlns:$site_ns" => $LJ::SITEROOT,
        },
        "Check namespaces for feed"
    );

    my ( $feed, $error ) = LJ::ParseFeed::parse_feed( $feed_xml, "atom" );

    my $userid = $u->userid;
    my $e1id   = $e1->ditemid;

    my $feed_entryid = delete $feed->{items}->[1]->{id};
    delete $feed->{items}->[0]->{id};
    like( $feed_entryid, qr/tag:$LJ::DOMAIN,\d{4}-\d{2}-\d{2}:$userid:$e1id/, "Feed entry id" );

    is_deeply(
        $feed->{items},
        [
            {
                link    => $e2->url,
                subject => $e2->subject_raw,
                text    => event_with_commentimage($e2),
                time    => substr( $e2->eventtime_mysql, 0, -3 ),
                author  => $u->name_raw,
            },
            {
                link    => $e1->url,
                subject => $e1->subject_raw,
                text    => event_with_commentimage($e1),
                time    => substr( $e1->eventtime_mysql, 0, -3 ),
                author  => $u->name_raw,
            }
        ],
        "Check entries from feed"
    );

    note("Posted entry: individual item");
    my $e2id = $e2->ditemid;
    my $r2   = DW::Request::Standard->new(
        HTTP::Request->new( GET => $u->journal_base . "/data/atom?itemid=$e2id" ) );

    $feed_xml = LJ::Feed::make_feed( $r2, $u, $remote, { pathextra => "/atom" } );
    ( $feed, $error ) = LJ::ParseFeed::parse_feed( $feed_xml, "atom" );
    delete $feed->{items}->[0]->{id};
    is_deeply(
        $feed->{items}->[0],
        {
            link    => $e2->url,
            subject => $e2->subject_raw,
            text    => event_with_commentimage($e2),
            time    => substr( $e2->eventtime_mysql, 0, -3 ),
            author  => $u->name_raw,
        },
        "Check individual entry from feed"
    );
}

note("Icon feed");
SKIP: {
    my $num_tests = 1;

    use FindBin qw($Bin);
    chdir "$Bin/data/userpics" or skip "Failed to chdir to t/data/userpics", $num_tests;
    open( my $fh, 'good.png' ) or skip "No icon", $num_tests;

    my $ICON = do { local $/; <$fh> };
    my $icon = LJ::Userpic->create( $u, data => \$ICON );

    my $icons_r = DW::Request::Standard->new(
        HTTP::Request->new( GET => $u->journal_base . "/data/userpics" ) );

    my $feed_xml = LJ::Feed::make_feed( $icons_r, $u, $remote, { pathextra => "/userpics" } );

    my $parser = new XML::Parser( Style => 'Objects' );
    my $parsed = $parser->parse($feed_xml);
    $parsed = $parsed->[0];
    delete $parsed->{Kids};
    is_deeply(
        $parsed,
        {
            'xmlns' => "http://www.w3.org/2005/Atom",
        },
        "Check namespaces for feed"
    );

}

note("No bot crawling");
{
    # block robots from crawling, but normal feed readers
    # should still be able to read the feed
    $u->set_prop( "opt_blockrobots", 1 );

    my $feed_xml = LJ::Feed::make_feed( $r, $u, $remote, { pathextra => "/atom" } );

    my $parser = new XML::Parser( Style => 'Objects' );
    my $parsed = $parser->parse($feed_xml);
    $parsed = $parsed->[0];
    delete $parsed->{Kids};
    is_deeply(
        $parsed,
        {
            'xmlns'          => "http://www.w3.org/2005/Atom",
            "xmlns:$site_ns" => $LJ::SITEROOT,
            'xmlns:idx'      => 'urn:atom-extension:indexing',
            'idx:index'      => 'no',
        },
        "Atom indexing extension"
    );

    my ( $feed, $error ) = LJ::ParseFeed::parse_feed( $feed_xml, "atom" );
    delete $_->{id} foreach @{ $feed->{items} || [] };
    is_deeply(
        $feed->{items},
        [
            {
                link    => $e2->url,
                subject => $e2->subject_raw,
                text    => event_with_commentimage($e2),
                time    => substr( $e2->eventtime_mysql, 0, -3 ),
                author  => $u->name_raw,
            },
            {
                link    => $e1->url,
                subject => $e1->subject_raw,
                text    => event_with_commentimage($e1),
                time    => substr( $e1->eventtime_mysql, 0, -3 ),
                author  => $u->name_raw,
            }
        ],
        "Check entries from feed"
    );
}

