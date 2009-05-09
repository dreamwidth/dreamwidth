#!/usr/bin/perl
#
# LJ::Event::XPostFailure
#
# Event for crosspost failure
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package LJ::Event::XPostFailure;
use strict;
use base 'LJ::Event';
use Carp qw/ croak /;
use Storable qw/ nfreeze thaw /;

sub new {
    my ( $class, $u, $acctid, $ditemid, $errmsg ) = @_;
    $u = LJ::want_user( $u )
        or croak 'Invalid LJ::User object passed.';

    # we're overloading the import_status table.  they won't notice.
    my $sid = LJ::alloc_user_counter( $u, 'Z' );
    if ( $sid ) {
        # build the ref we'll store
        my $optref = {
            ditemid => $ditemid+0,
            acctid => $acctid+0,
            errmsg => $errmsg,
        };

        # now attempt to store it
        $u->do( 'INSERT INTO import_status (userid, import_status_id, status) VALUES (?, ?, ?)',
                undef, $u->id, $sid, nfreeze( $optref ) );
        return $class->SUPER::new( $u, $sid );
    }

    # we failed somewhere
    return undef;
}

# for this to be on for all users
# FIXME we should allow users to unsubscribe to these notifications
sub is_common { 1 }

sub is_visible { 1 }

sub is_significant { 1 }

sub always_checked { 1 }


sub content {
    my $self = $_[0];
    return BML::ml( 'event.xpost.failure.content',
            {
                accountname => $self->account->displayname,
                errmsg => $self->errmsg,
            } );
}

# the main title for the event
sub as_html {
    my $self = $_[0];

    my $subject = $self->entry->subject_html ?  $self->entry->subject_html : BML::ml('event.xpost.nosubject');
    return BML::ml('event.xpost.failure.title', { accountname => $self->account->displayname, entrydesc => $subject, entryurl => $self->entry->url });

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
    return $_[0]->_optsref->{acctid};
}


sub ditemid {
    return $_[0]->_optsref->{ditemid};
}


sub errmsg {
    return $_[0]->_optsref->{errmsg};
}


# the account crossposted to
sub account {
    my $self = $_[0];
    return $self->{account} ||=
        DW::External::Account->get_external_account( $self->u, $self->acctid );
}


# the entry crossposted
sub entry {
    my $self = $_[0];
    return $self->{entry} ||= LJ::Entry->new( $self->u, ditemid => $self->ditemid );
}


# load our options hashref which contains most of the information we
# are actually interested in
sub _optsref {
    my $self = $_[0];
    return $self->{_optsref} if $self->{_optsref};

    my $u = $self->u;
    my $item = $u->selectrow_array(
        'SELECT status FROM import_status WHERE userid = ? AND import_status_id = ?',
        undef, $u->id, $self->arg1
    );
    return undef
        if $u->err || ! $item;

    return $self->{_optsref} = thaw( $item );
}


1;
