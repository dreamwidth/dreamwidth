# t/synsuck-subject.t
#
# Test the visible subject and tooltip of imported feed entries.
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

use File::Temp qw(tempdir);
use Test::More;
use HTML::Parser;
use HTTP::Request;
use HTTP::Response;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
use LJ::S2;
use LJ::SynSuck;
use LJ::Test qw(temp_feed);

local $LJ::TASK_QUEUE_BACKEND    = 'localdisk';
local $LJ::TASK_QUEUE_LOCAL_PATH = tempdir( CLEANUP => 1 );

my $feed = temp_feed();
my $dbh  = LJ::get_db_writer();
my $urow = $dbh->selectrow_hashref(
    'SELECT u.user, s.* FROM user u JOIN syndicated s USING (userid) WHERE s.userid = ?',
    undef, $feed->id );

END {
    if ($feed) {
        my $items = $feed->selectcol_arrayref( 'SELECT jitemid FROM log2 WHERE journalid = ?',
            undef, $feed->id );
        LJ::delete_entry( $feed, $_ ) for @$items;
        $dbh->do( 'DELETE FROM synitem WHERE userid = ?', undef, $feed->id );
    }
}

sub import_subject {
    my ( $subject, $fixture ) = @_;
    $fixture //= 'fixture-1';
    my $title = LJ::ehtml($subject);
    my $rss   = qq{<?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel><title>Example feed</title>
        <link>https://example.com/</link><description>Synthetic feed</description>
        <item><title>$title</title><link>https://example.com/1</link>
        <guid isPermaLink="false">$fixture</guid><description>Example item.</description></item>
        </channel></rss>};
    my $response = HTTP::Response->new(200);
    $response->header( 'Content-Type' => 'application/rss+xml' );
    ok( LJ::SynSuck::process_content( $urow, [ $response, $rss ] ), 'feed item imported' );
}

sub rendered_subject {
    my ( $itemid, $view ) = @_;
    LJ::start_request();
    DW::Request->reset;
    my $entry   = LJ::Entry->new( $feed, jitemid => $itemid );
    my $request = DW::Request::Standard->new(
        HTTP::Request->new( GET => 'http://localhost/' . $entry->ditemid . '.html' ) );
    my $ctx = [];
    my $s2entry;
    if ( $view eq 'entry' ) {
        ( undef, $s2entry ) = LJ::S2::EntryPage_entry( $feed, undef,
            { getargs => {}, ctx => $ctx, r => $request, ljentry => $entry } );
    }
    else {
        $s2entry = LJ::S2::Entry_from_entryobj( $feed, $entry,
            { getargs => {}, no_entry_body => 1, ctx => $ctx } );
    }
    local $LJ::S2::CURR_PAGE = { view => $view };
    my $html = S2::Builtin::LJ::Entry__formatted_subject( $ctx, $s2entry, {} );

    my ( $attrs, $visible );
    my $parser = HTML::Parser->new(
        api_version => 3,
        start_h     => [ sub { $attrs = $_[1] if $_[0] eq 'a' }, 'tagname,attr' ],
        text_h      => [ sub { $visible .= $_[0] }, 'dtext' ],
    );
    $parser->parse($html)->eof;
    return ( $attrs->{title}, $visible );
}

my $visible = 'A' x LJ::CMAX_SUBJECT;
my $suffix  = q{ The rest of the feed title says "read on" & doesn't end here.} x 4;
import_subject("$visible$suffix First ending.");
my ($itemid) =
    $feed->selectrow_array( 'SELECT jitemid FROM log2 WHERE journalid = ?', undef, $feed->id );
BAIL_OUT('Feed entry was not created') unless $itemid;

for my $view ( 'recent', 'entry' ) {
    my ( $tooltip, $display ) = rendered_subject( $itemid, $view );
    is( $display, $visible, "$view: visible subject stays truncated" );
    is( $tooltip, "$visible$suffix First ending.", "$view: tooltip contains the full subject" );
}

import_subject("$visible$suffix Revised ending.");
my $journalid = $feed->id;
my $clusterid = $feed->clusterid;
LJ::MemCache::delete( [ $journalid, "logtext:$clusterid:$journalid:$itemid" ] );
my ( $tooltip, $display ) = rendered_subject( $itemid, 'recent' );
is( $display, $visible, 'editing beyond the limit does not change the visible subject' );
is( $tooltip, "$visible$suffix Revised ending.", 'tooltip follows edits beyond the limit' );

my $short = q{A "short" replacement & its ending};
import_subject($short);
( $tooltip, $display ) = rendered_subject( $itemid, 'recent' );
is( $display, $short,   'visible subject follows a short replacement' );
is( $tooltip, $display, 'short replacement does not have a stale long tooltip' );

my $oversized_itemid;
my $multibyte = "\xE2\x98\x83";
for my $letter ( 'B', 'C' ) {
    my $prefix = ( $letter x 4092 ) . $multibyte;
    import_subject( $prefix . $multibyte . ( 'Z' x 16_777_216 ), 'oversized' );
    my ( $stored_id, $stored_subject, $stored_body, $stored_tooltip ) = $feed->selectrow_array(
        'SELECT jitemid, subject, event, syn_full_subject FROM logtext2 '
            . 'WHERE journalid = ? AND jitemid <> ?',
        undef, $feed->id, $itemid
    );
    $oversized_itemid //= $stored_id;
    ok(
        $stored_id && $stored_id == $oversized_itemid,
        'oversized title imports or updates the same entry'
    );
    is( $stored_subject, $letter x LJ::CMAX_SUBJECT, 'oversized title keeps the standard subject' );
    like(
        LJ::text_uncompress( $stored_body // '' ),
        qr/Example item\./,
        'oversized title keeps the entry body'
    );
    ok( defined $stored_tooltip && $stored_tooltip eq $prefix,
        'stored tooltip stays within the byte budget without splitting UTF-8' );
}

done_testing;
