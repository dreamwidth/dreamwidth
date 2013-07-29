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
use List::MoreUtils qw/uniq/;

use base 'LJ::Event::JournalNewComment';

sub zero_journalid_subs_means { return 'all'; }

sub subscription_as_html {
    my ( $class, $subscr, $key_prefix ) = @_;

    my $key = $key_prefix || 'event.journal_new_comment.reply';
    my $arg2 = $subscr->arg2;

    my %key_suffixes = (
        0 => '.comment',
        1 => '.community',
        2 => '.mycomment',
    );

    return BML::ml( $key . $key_suffixes{$arg2} );
}

sub available_for_user {
    return 1;
}

sub _relevant_userids {
    my $comment = $_[0]->comment;
    return () unless $comment;

    my @prepart;
    push @prepart, $comment->posterid if $comment->posterid;

    my $parent = $comment->parent;

    return uniq ( @prepart, $parent->posterid )
        if $parent && $parent->posterid;

    my $entry = $comment->entry;
    return () unless $entry;

    return uniq ( @prepart ) unless $entry->journal->is_community;

    return uniq ( @prepart, $entry->posterid );
}

sub early_filter_event {
    my @userids = _relevant_userids( $_[1] );
    return scalar @userids ? 1 : 0;
}

sub additional_subscriptions_sql {
    my @userids = _relevant_userids( $_[1] );
    return ('userid IN (' . join(",", map { '?' } @userids) . ')', @userids) if scalar @userids;
    return undef;
}

# override parent class sbuscriptions method to
# convert opt_gettalkemail to a subscription
sub raw_subscriptions {
    my ($class, $self, %args) = @_;
    my $cid   = delete $args{'cluster'};
    croak("Cluser id (cluster) must be provided") unless defined $cid;

    my $scratch = delete $args{'scratch'}; # optional

    croak("Unknown options: " . join(', ', keys %args)) if %args;
    croak("Can't call in web context") if LJ::is_web_context();

    my @userids = _relevant_userids( $_[1] );

    return eval { LJ::Event::raw_subscriptions($class, $self,
        cluster => $cid, scratch => $scratch ) } unless scalar @userids;

    my @rows = eval { LJ::Event::raw_subscriptions($class, $self,
        cluster => $cid, scratch => $scratch ) };

    foreach my $userid ( @userids ) {
        my $u = LJ::load_userid($userid);
        next unless $u;
        next unless ( $cid == $u->clusterid );

        if ( $u->prop('opt_gettalkemail') eq 'Y' ) {
            push @rows, map{ LJ::Subscription->new_from_row($_) } map { (
                # FIXME(dre): Remove when ESN can bypass inbox
                {
                    userid  => $userid,
                    ntypeid => LJ::NotificationMethod::Inbox->ntypeid, # Inbox
                    etypeid => $class->etypeid,
                    arg2 => $_,
                },
                {
                    userid  => $userid,
                    ntypeid => LJ::NotificationMethod::Email->ntypeid, # Email
                    etypeid => $class->etypeid,
                    arg2 => $_,
                },
            ) } ( 0, 1 );
        }

        if ( $u->prop('opt_getselfemail') eq '1' ) {
            push @rows, map{ LJ::Subscription->new_from_row($_) } (
                # FIXME(dre): Remove when ESN can bypass inbox
                {
                    userid  => $userid,
                    ntypeid => LJ::NotificationMethod::Inbox->ntypeid, # Inbox
                    etypeid => $class->etypeid,
                    arg2 => 2,
                },
                {
                    userid  => $userid,
                    ntypeid => LJ::NotificationMethod::Email->ntypeid, # Email
                    etypeid => $class->etypeid,
                    arg2 => 2,
                },
            );
        }
    }

    return @rows;
}

sub matches_filter {
    my ($self, $subscr) = @_;

    my $sjid = $subscr->journalid;
    my $ejid = $self->event_journal->{userid};
    my $watcher = $subscr->owner;
    my $arg2 = $subscr->arg2;

    my $comment = $self->comment;

    # Do not send on own comments

    return 0 unless $comment->visible_to( $watcher );

    my $parent = $comment->parent;

    if ( $arg2 == 0 ) {
        # Someone replies to my comment
        return 0 unless $parent;
        return 0 unless $parent->posterid == $watcher->id;
        
        # Make sure we didn't post the comment
        return 1 unless $comment->posterid == $watcher->id;
    } elsif ( $arg2 == 1 ) {
        # Someone replies to my entry in a community
        my $entry = $comment->entry;
        return 0 unless $entry;

        # Make sure the entry is posted by the watcher
        return 0 unless $entry->posterid == $watcher->id;

        # Make sure we didn't post the comment
        return 1 unless $comment->posterid == $watcher->id;
    } elsif ( $arg2 == 2 ) {
        # I comment on any entry in someone else's journal
        my $entry = $comment->entry;
        return 0 unless $entry;

        # Make sure we posted the comment
        return 1 if $comment->posterid == $watcher->id;
    }

    return 0;
}

1;

