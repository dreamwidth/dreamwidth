#!/usr/bin/perl
# t/latest-feed.t
#
# Latest Things honors entry ratings while preserving journal defaults and opt-outs.
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
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm with_fake_memcache);
use DW::LatestFeed;

my $poster    = temp_user();
my $commenter = temp_user();
my $comm      = temp_comm();
$_->update_self( { status => 'A', statusvis => 'V' } ) for $poster, $commenter, $comm;

sub check_feed {
    my ( $entry, $comment, $expected, $description, $future ) = @_;
    my $time = $future ? time() + 300 : 0;
    LJ::MemCache::delete('latest_queue_next');
    LJ::MemCache::delete('latest_items');
    LJ::MemCache::set(
        latest_queue => [
            {
                type      => 'entry',
                journalid => $entry->journalid,
                jitemid   => $entry->jitemid,
                t         => $time
            },
            {
                type      => 'comment',
                journalid => $entry->journalid,
                jtalkid   => $comment->jtalkid,
                t         => $time
            },
        ]
    );

    # This test owns its isolated fake queue; no shared queue lock is needed.
    DW::LatestFeed->_process_queue( have_lock => 1 );
    my $items = LJ::MemCache::get('latest_items') || [];
    for my $type (qw(entry comment)) {
        is( scalar( grep { $_->{type} eq $type } @$items ), $expected, "$description ($type)" );
    }
}

with_fake_memcache {
    for my $journal ( $poster, $comm ) {
        my $entry = $poster->t_post_fake_entry(
            usejournal      => $journal->user,
            usejournal_okay => 1
        );
        my $comment = $entry->t_enter_comment( u => $commenter );
        for my $journal_rating (qw(none concepts explicit)) {
            $journal->set_prop( adult_content => $journal_rating );
            for my $case (
                [ '',               'unset',          $journal_rating eq 'none' ? 1 : 0 ],
                [ 'none',           'all ages',       1 ],
                [ 'concepts',       'discretion',     0 ],
                [ 'explicit',       'explicit',       0 ],
                [ 'invalid-rating', 'legacy invalid', $journal_rating eq 'none' ? 1 : 0 ],
                )
            {
                $entry->set_prop( adult_content => $case->[0] );
                check_feed( $entry, $comment, $case->[2],
                    $journal->journaltype . " journal $journal_rating / entry $case->[1]" );
            }
        }
        $entry->set_prop( adult_content            => 'none' );
        $entry->set_prop( adult_content_maintainer => 'explicit' );
        check_feed( $entry, $comment, 0, 'maintainer restriction wins over all ages' );
        $entry->set_prop( adult_content_maintainer => '' );
        $journal->set_prop( latest_optout => 1 );
        check_feed( $entry, $comment, 0, 'journal opt-out is preserved' );
        $journal->clear_prop('latest_optout');
        $poster->set_prop( latest_optout => 1 );
        check_feed( $entry, $comment, 0, 'entry poster opt-out is preserved' );
        $poster->clear_prop('latest_optout');
        $entry->set_prop( opt_backdated => 1 );
        check_feed( $entry, $comment, 0, 'backdated all-ages entry remains excluded' );
        $entry->set_prop( opt_backdated => 0 );
        check_feed( $entry, $comment, 0, 'five-minute delay is preserved', 1 );
    }

    my $private = $poster->t_post_fake_entry( security => 'private' );
    $private->set_prop( adult_content => 'none' );
    my $comment = $private->t_enter_comment( u => $poster );
    check_feed( $private, $comment, 0, 'private all-ages entry remains excluded' );
};

done_testing();
