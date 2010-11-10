#!/usr/bin/perl
#
# LJ::Event::XPostSuccess
#
# Event for crosspost success
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package LJ::Event::XPostSuccess;
use strict;
use base 'LJ::Event';
use Carp qw(croak);

sub new {
    my ( $class, $u, $acctid, $ditemid ) = @_;
    croak 'Not an LJ::User' unless LJ::isu($u);
    return $class->SUPER::new( $u, $acctid, $ditemid );
}

# for this to be on for all users
# FIXME we should allow users to unsubscribe to these notifications
sub is_common { 1 }

sub is_visible { 1 }

sub is_significant { 1 }

sub always_checked { 1 }

# FIXME make this more useful, like include a link to the crosspost
sub content {
    my ($self) = @_;
    if ( $self->account ) {
        return BML::ml( 'event.xpost.success.content', { accountname => $self->account->displayname } );
    } else {
        return BML::ml( 'event.xpost.noaccount' );
    }
}

# short enough that we can just use this the normal content as the summary
sub content_summary {
    return $_[0]->content( @_ );
}

# the main title for the event
sub as_html {
    my $self = $_[0];
    my $subject = $self->entry->subject_html ?  $self->entry->subject_html : BML::ml('event.xpost.nosubject');

    if ( $self->account ) {
        return BML::ml( 'event.xpost.success.title',
            {
                accountname => $self->account->displayname,
                entrydesc => $subject,
                entryurl => $self->entry->url
            } );

    } else {
        return BML::ml( 'event.xpost.noaccount' );
    }
}

# available for all users.
sub available_for_user  {
    my ( $class, $u, $subscr ) = @_;
    return 1;
}

# override parent class sbuscriptions method to always return
# a subscription object for the user
sub subscriptions {
    my ( $self, %args ) = @_;
    my $cid   = delete $args{'cluster'};  # optional
    my $limit = delete $args{'limit'};    # optional
    croak("Unknown options: " . join(', ', keys %args)) if %args;
    croak("Can't call in web context") if LJ::is_web_context();

    my @subs;
    my $u = $self->u;
    return unless $cid == $u->clusterid;

    my $row = { userid  => $self->u->id,
                ntypeid => LJ::NotificationMethod::Inbox->ntypeid, # Inbox
              };

    push @subs, LJ::Subscription->new_from_row($row);

    push @subs, eval { $self->SUPER::subscriptions(cluster => $cid,
                                                   limit   => $limit) };

    return @subs;
}

sub get_subscriptions {
    my ( $self, $u, $subid ) = @_;

    unless ($subid) {
        my $row = { userid  => $u->{userid},
                    ntypeid => LJ::NotificationMethod::Inbox->ntypeid, # Inbox
                  };

        return LJ::Subscription->new_from_row($row);
    }

    return $self->SUPER::get_subscriptions($u, $subid);
}

sub acctid {
    return $_[0]->arg1;
}

sub ditemid {
    return $_[0]->arg2;
}

# the account crossposted to
sub account {
    my ($self) = @_;
    return $_[0]->{account} if $_[0]->{account};
    $_[0]->{account} = DW::External::Account->get_external_account($self->u, $self->acctid);
    return $_[0]->{account};
}

# the entry crossposted
sub entry {
    my ($self) = @_;
    return $self->{entry} if $self->{entry};
    $_[0]->{entry} = LJ::Entry->new($self->u, ( ditemid => $self->ditemid ));
    return $self->{entry};
}


1;
