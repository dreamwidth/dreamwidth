#!/usr/bin/perl
#
# LJ::Event::JournalNewComment::Reply - Someone replies to any comment I make
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package LJ::Event::JournalNewComment::Reply;
use strict;

use base 'LJ::Event::JournalNewComment';

sub zero_journalid_subs_means { return 'all'; }

sub additional_subscriptions_sql {
    my $comment = $_[0]->comment;
    my $parent = $comment->parent;

    # FIXME: Early bail?
    return ('0 = 1') unless $parent;
    return ('0 = 1') unless $parent->posterid;

    return ('userid = ?', $parent->posterid);
}

sub matches_filter {
    my ($self, $subscr) = @_;

    my $sjid = $subscr->journalid;
    my $ejid = $self->event_journal->{userid};

    my $comment = $self->comment;
    my $entry = $comment->entry;
    return 0 unless $entry;

    my $watcher = $subscr->owner;
    return 0 unless $comment->visible_to( $watcher );

    return 1;
}

1;

