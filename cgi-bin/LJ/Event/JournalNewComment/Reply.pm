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

sub subscription_as_html {
    my ( $class, $subscr, $key_prefix ) = @_;


    my $key = $key_prefix || 'event.journal_new_comment';

    return BML::ml( $key . ".reply" );
}

sub _shared_checks {
    my $comment = $_[0]->comment;
    my $parent = $comment->parent;

    return ('userid = ?', $parent->posterid)
        if ( $parent && $parent->posterid );

    my $entry = $comment->entry;
    return (undef) unless $entry;

    return ('userid = ?', $entry->posterid);
}

sub early_filter_event {
    my ($v,@args) = _shared_checks($_[1]);
    return ( defined $v ) ? 1 : 0;
}

sub additional_subscriptions_sql {
    return _shared_checks($_[1]);
}

sub matches_filter {
    my ($self, $subscr) = @_;

    my $sjid = $subscr->journalid;
    my $ejid = $self->event_journal->{userid};

    my $comment = $self->comment;
    my $parent = $comment->parent;
    return 0 if $parent && $comment->posterid == $parent->posterid;

    my $entry = $comment->entry;
    return 0 unless $entry;
    return 0 if $comment->posterid == $entry->posterid;

    my $watcher = $subscr->owner;
    return 0 unless $comment->visible_to( $watcher );

    return 1;
}

1;

