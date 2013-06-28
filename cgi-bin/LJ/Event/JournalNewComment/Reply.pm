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

sub _relevant_userid {
    my $comment = $_[0]->comment;
    my $parent = $comment->parent;

    return $parent->posterid
        if ( $parent && $parent->posterid );

    my $entry = $comment->entry;
    return undef unless $entry;

    return $entry->posterid;
}

sub early_filter_event {
    my $userid = _relevant_userid( $_[1] );
    return ( $userid ) ? 1 : 0;
}

sub additional_subscriptions_sql {
    my $userid = _relevant_userid( $_[1] );
    return ('userid = ?', $userid) if $userid;
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

    my $userid = _relevant_userid( $_[1] );

    return eval { LJ::Event::raw_subscriptions($class, $self,
        cluster => $cid, scratch => $scratch ) } unless $userid;


    my $u = LJ::load_userid($userid);
    return unless ( $cid == $u->clusterid );

    return eval { LJ::Event::raw_subscriptions($class, $self,
        cluster => $cid, scratch => $scratch ) }
            if $u->prop('opt_gettalkemail') eq 'X';

    return () if $u->prop('opt_gettalkemail') ne 'Y';

    my @rows = (
            # FIXME(dre): Remove when ESN can bypass inbox
            {
                userid  => $userid,
                ntypeid => LJ::NotificationMethod::Inbox->ntypeid, # Inbox
                etypeid => $class->etypeid,
            },
            {
                userid  => $userid,
                ntypeid => LJ::NotificationMethod::Email->ntypeid, # Email
                etypeid => $class->etypeid,
            },
        );

    return map{ LJ::Subscription->new_from_row($_) } @rows;
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

