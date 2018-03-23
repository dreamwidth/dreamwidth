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

    my $entry = $comment->entry;
    return () unless $entry;

    my @prepart;
    push @prepart, $comment->posterid
        if $comment->posterid;

    my $parent = $comment->parent;

    push @prepart, $parent->posterid
        if $parent && $parent->posterid;

    push @prepart, $entry->posterid
        if $entry->journal->is_community;

    return uniq @prepart;
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

sub migrate_user {
    my ($class, $u) = @_;

    # Cannot use $u->migrate_prop_to_esn
    #  * opt_gettalkemail isn't really a prop
    #  * ->migrate_prop_to_esn won't take arg1/arg2
    #  * it no longer exists following https://github.com/dreamwidth/dw-free/issues/2052

    my $opt_gettalkemail = $u->prop('opt_gettalkemail') // '';
    my $opt_getselfemail = $u->prop('opt_getselfemail') // '';
    my @pending_subscriptions;

    if ( $opt_gettalkemail ne 'X' ) {
        if ( $opt_gettalkemail eq 'Y' ) {
            push @pending_subscriptions, map { (
                # FIXME(dre): Remove when ESN can bypass inbox
                LJ::Subscription::Pending->new($u,
                    event => 'JournalNewComment::Reply',
                    method => 'Inbox',
                    arg2 => $_,
                ),
                LJ::Subscription::Pending->new($u,
                    event => 'JournalNewComment::Reply',
                    method => 'Email',
                    arg2 => $_,
                ),
            ) } ( 0, 1 );
        }
        $u->update_self( { 'opt_gettalkemail' => 'X' } );
    }
    if ( $opt_getselfemail ne 'X' ) {
        if ( $opt_getselfemail eq '1' ) {
            push @pending_subscriptions, (
                # FIXME(dre): Remove when ESN can bypass inbox
                LJ::Subscription::Pending->new($u,
                    event => 'JournalNewComment::Reply',
                    method => 'Inbox',
                    arg2 => 2,
                ),
                LJ::Subscription::Pending->new($u,
                    event => 'JournalNewComment::Reply',
                    method => 'Email',
                    arg2 => 2,
                ),
            );
        }
        $u->set_prop( 'opt_getselfemail' => 'X' );
    }

    $_->commit foreach @pending_subscriptions;
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

    foreach my $userid ( @userids ) {
        my $u = LJ::load_userid($userid);
        next unless $u;
        next unless ( $cid == $u->clusterid );

        $class->migrate_user( $u );
    }

    return eval { LJ::Event::raw_subscriptions($class, $self,
        cluster => $cid, scratch => $scratch ) } unless scalar @userids;

    my @rows = eval { LJ::Event::raw_subscriptions($class, $self,
        cluster => $cid, scratch => $scratch ) };

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

    # Do not send if opt_noemail applies
    return 0 if $self->apply_noemail( $watcher, $comment, $subscr->method );

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

