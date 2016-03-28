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

use Test::More tests => 5;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test qw ( temp_user );
use LJ::Entry;

sub post_entry {
    my ( $u, $entries ) = @_;
    my $entry = $u->t_post_fake_entry( body => "test post " . time() . rand() );

    unshift @{ $entries->{$u->id} }, $entry;
    unshift @{ $entries->{all} }, $entry;
}

sub extract {
    my ( $items ) = @_;

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

note( " ### RECENT ITEMS ### ");
{
    my $u = temp_user();
    my $entries = {};

    post_entry( $u, $entries );
    post_entry( $u, $entries );
    post_entry( $u, $entries );

    my @entrylist = @{ $entries->{$u->id} || {} };
    LJ::Protocol::do_request( "editevent", {
        itemid      => $entrylist[1]->jitemid,
        ver         => 1,
        username    => $u->user,
        year        => "1999",  # arbitary early date
    }, undef, {
        noauth          => 1,
        use_old_content => 1,
    } );

    LJ::Entry->reset_singletons;
    $entrylist[1] = LJ::Entry->new( $u, jitemid => $entrylist[1]->jitemid );


    # fragile because we can't control the system log time
    # so instead, let's just skip this test if the generated entries
    # don't have a consistent logtime
    SKIP: {
        my $logtime = $entrylist[0]->logtime_unix;
        my $do_skip = 0;
        foreach ( @entrylist ) {
            $do_skip = 1 if $_->logtime_unix != $logtime;
        }

        skip "Test is fragile so we skip if the logtime isn't consistent among the newly-posted entries", 2 if $do_skip;

        # in user-visible display order
        # i.e., for personal journals
        my @recent_items = $u->recent_items(
            clusterid     => $u->{clusterid},
            clustersource => 'slave',
            itemshow      => 3,
        );
        is_deeply( [ map { $_->{itemid} } @recent_items ], [ 3, 1, 2 ], "Got entries back, ordered by the user-specified date." );

        # in system time order
        # i.e., communities and feeds
        @recent_items = $u->recent_items(
            clusterid     => $u->{clusterid},
            clustersource => 'slave',
            itemshow      => 3,
            order         => "logtime",
        );
        is_deeply( [ map { $_->{itemid} } @recent_items ], [ 3, 2, 1 ], "Got entries back, ordered by the system-recorded date." );

    }
}


note( " ### WATCH ITEMS ### " );
note( "basic merging of watched items from different users, no security" );
{
    my $u = temp_user();

    my $w1 = temp_user();
    my $w2 = temp_user();
    my $entries = {};

    post_entry( $w1, $entries ); sleep( 1 );
    post_entry( $w2, $entries ); sleep( 1 );
    post_entry( $w1, $entries );

    my @watch_items = $u->watch_items( itemshow => 3 );
    is_deeply( \@watch_items, [], "No watch items" );

    $u->add_edge( $w1, watch => {} );
    @watch_items = $u->watch_items( itemshow => 3 );
    is_deeply(  extract( \@watch_items ), extract( $entries->{$w1->id} ), "Items from \$w1" );

    $u->add_edge( $w2, watch => {} );
    @watch_items = $u->watch_items( itemshow => 3 );
   is_deeply( extract( \@watch_items ), extract( $entries->{all} ), "Items from \$w1 and \$w2" );
}
