# t/log-items.t
#
# Test TODO logging of posts??
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

use Test::More tests => 19;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test qw ( temp_user );
use LJ::Entry;
use LJ::Tags;

sub post_entry {
    my ( $u, $entries ) = @_;
    my $entry = $u->t_post_fake_entry( body => "test post " . time() . rand() );

    unshift @{ $entries->{ $u->id } }, $entry;
    unshift @{ $entries->{all} }, $entry;
}

sub extract {
    my ($items) = @_;

    my @keys = qw( posterid jitemid );
    my @ret;

    foreach my $item ( @{ $items || {} } ) {

        # extract the important attributes for comparison
        my $entry = {};
        $entry->{$_} = $item->{$_} foreach @keys;
        push @ret, $entry;
    }

    return \@ret;
}

note(" ### RECENT ITEMS ### ");
{
    my $u       = temp_user();
    my $entries = {};

    post_entry( $u, $entries );
    post_entry( $u, $entries );
    post_entry( $u, $entries );

    my @entrylist = @{ $entries->{ $u->id } || {} };
    LJ::Protocol::do_request(
        "editevent",
        {
            itemid   => $entrylist[1]->jitemid,
            ver      => 1,
            username => $u->user,
            year     => "1999",                   # arbitary early date
        },
        undef,
        {
            noauth          => 1,
            use_old_content => 1,
        }
    );

    LJ::Entry->reset_singletons;
    $entrylist[1] = LJ::Entry->new( $u, jitemid => $entrylist[1]->jitemid );

    # fragile because we can't control the system log time
    # so instead, let's just skip this test if the generated entries
    # don't have a consistent logtime
SKIP: {
        my $logtime = $entrylist[0]->logtime_unix;
        my $do_skip = 0;
        foreach (@entrylist) {
            $do_skip = 1 if $_->logtime_unix != $logtime;
        }

        skip
"Test is fragile so we skip if the logtime isn't consistent among the newly-posted entries",
            2
            if $do_skip;

        # in user-visible display order
        # i.e., for personal journals
        my @recent_items = $u->recent_items(
            clusterid     => $u->{clusterid},
            clustersource => 'slave',
            itemshow      => 3,
        );
        is_deeply(
            [ map { $_->{itemid} } @recent_items ],
            [ 3, 1, 2 ],
            "Got entries back, ordered by the user-specified date."
        );

        # in system time order
        # i.e., communities and feeds
        @recent_items = $u->recent_items(
            clusterid     => $u->{clusterid},
            clustersource => 'slave',
            itemshow      => 3,
            order         => "logtime",
        );
        is_deeply(
            [ map { $_->{itemid} } @recent_items ],
            [ 3, 2, 1 ],
            "Got entries back, ordered by the system-recorded date."
        );

    }
}

note(" ### TAG-FILTERED RECENT ITEMS ### ");
{
    my $journal = temp_user();
    my $time    = 1_700_000_000;
    my $tag     = 'paged';
    my $untagged;
    my @tagged;

    foreach my $index ( 0 .. 8 ) {
        my $entry = $journal->t_post_fake_entry(
            body     => "Tag paging fixture $index",
            security => $index == 8 ? 'private' : 'public',
        );
        my $id = $entry->jitemid;
        my $stamp =
            $index == 8 ? $time + 120 : $index == 0 ? $time + 60 : $index == 6 ? $time - 60 : $time;
        my $date         = LJ::mysql_time( $stamp, 1 );
        my $reverse_time = $LJ::EndOfTime - $stamp;
        $journal->do(
            'UPDATE log2 SET eventtime = ?, logtime = ?, revttime = ?, rlogtime = ?
             WHERE journalid = ? AND jitemid = ?',
            undef, $date, $date, $reverse_time, $reverse_time, $journal->id, $id
        ) or die $journal->errstr;
        $untagged = $id if $index == 7;
        next if $index >= 7;
        LJ::Tags::update_logtags( $journal, $id, { remote => $journal, add => [$tag] } )
            or die "Could not tag entry $id";
        push @tagged, $id;
    }

    my $tags = LJ::Tags::get_usertags($journal);
    my ($tagid) = grep { $tags->{$_}->{name} eq $tag } keys %$tags;
    die "Missing test tag $tag" unless defined $tagid;

    my @expected = ( $tagged[0], reverse( @tagged[ 1 .. 5 ] ), $tagged[6] );
    my @public   = ( $expected[0], $untagged, @expected[ 1 .. 6 ] );
    foreach my $order ( 'eventtime', 'logtime' ) {
        my $page = sub {
            my ( $skip, $itemshow, %options ) = @_;
            return map { $_->{itemid} } $journal->recent_items(
                clusterid     => $journal->clusterid,
                clustersource => 'slave',
                order         => $order,
                dateformat    => 'S2',
                tagids        => [$tagid],
                tagmode       => 'or',
                itemshow      => $itemshow,
                skip          => $skip,
                %options,
            );
        };

        my @offsets = ( 0, 2, 4, 6 );
        is_deeply( [ map { $page->( $_, 2 ) } @offsets ],
            \@expected,
            "$order: two-entry pages return every tagged entry in order, exactly once" );
        my @displayed;
        foreach my $offset (@offsets) {
            my @items = $page->( $offset, 3 );
            pop @items if @items > 2;
            push @displayed, @items;
        }
        is_deeply( \@displayed, \@expected,
            "$order: dropping each lookahead entry leaves no duplicates or omissions" );
        is_deeply(
            [ $page->( 1, 3 ) ],
            [ @expected[ 1 .. 3 ] ],
            "$order: changing the page size and offset preserves tie order"
        );
        is_deeply( [ $page->( 7, 2 ) ], [], "$order: paging past the last entry returns nothing" );
        is_deeply(
            [ $page->( 0, 10, notafter => $LJ::EndOfTime - $time ) ],
            [ @expected[ 0 .. 5 ] ],
            "$order: the timestamp bound includes entries tied at the cutoff but no older entries"
        );
        is_deeply( [ map { $page->( $_, 2, tagids => undef ) } @offsets ],
            \@public, "$order: unfiltered pages keep all visible entries in order" );
        is_deeply(
            [ $page->( 0, 10, tagids => undef, notafter => $LJ::EndOfTime - $time ) ],
            [ @public[ 0 .. 6 ] ],
            "$order: a short unfiltered page respects visibility and the timestamp bound"
        );
    }
}

note(" ### WATCH ITEMS ### ");
note("basic merging of watched items from different users, no security");
{
    my $u = temp_user();

    my $w1      = temp_user();
    my $w2      = temp_user();
    my $entries = {};

    post_entry( $w1, $entries );
    sleep(1);
    post_entry( $w2, $entries );
    sleep(1);
    post_entry( $w1, $entries );

    my @watch_items = $u->watch_items( itemshow => 3 );
    is_deeply( \@watch_items, [], "No watch items" );

    $u->add_edge( $w1, watch => {} );
    @watch_items = $u->watch_items( itemshow => 3 );
    is_deeply( extract( \@watch_items ), extract( $entries->{ $w1->id } ), "Items from \$w1" );

    $u->add_edge( $w2, watch => {} );
    @watch_items = $u->watch_items( itemshow => 3 );
    is_deeply( extract( \@watch_items ), extract( $entries->{all} ), "Items from \$w1 and \$w2" );
}
