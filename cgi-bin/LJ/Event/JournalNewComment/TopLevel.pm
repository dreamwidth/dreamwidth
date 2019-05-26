#!/usr/bin/perl
#
# LJ::Event::JournalNewComment::TopLevel - Event that's fired when someone makes a new top-level comment to an entry
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package LJ::Event::JournalNewComment::TopLevel;
use strict;

use base 'LJ::Event::JournalNewComment';

sub subscription_as_html {
    return LJ::Event::JournalNewComment->subscription_as_html( $_[1],
        "event.journal_new_top_comment" );
}

sub matches_filter {
    my ( $self, $subscr ) = @_;

    return 0 unless $subscr->available_for_user;

    my $sjid = $subscr->journalid;
    my $ejid = $self->event_journal->{userid};

    # check that subscription's journal is the same as event's journal
    return 0 if $sjid && $sjid != $ejid;

    my $comment = $self->comment;
    my $entry   = $comment->entry;
    return 0 unless $entry;

    # no notifications unless they can see the comment
    my $watcher = $subscr->owner;
    return 0 unless $comment->visible_to($watcher);

    # check that event's entry is the entry we're interested in (subscribed to)
    my $wanted_ditemid = $subscr->arg1;
    return 0 if $wanted_ditemid && $entry->ditemid != $wanted_ditemid;

    # we're only interested if it's a top-level comment
    return 1 unless $comment->parenttalkid;

    return 0;
}

1;
