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
    $u = LJ::want_user($u)
        or croak 'Invalid LJ::User object passed.';

    # we're overloading the import_status table.  they won't notice.
    my $sid = LJ::alloc_user_counter( $u, 'Z' );
    if ($sid) {

        # build the ref we'll store
        my $optref = {
            ditemid => $ditemid + 0,
            acctid  => $acctid + 0,
            errmsg  => $errmsg,
        };

        # now attempt to store it
        $u->do( 'INSERT INTO import_status (userid, import_status_id, status) VALUES (?, ?, ?)',
            undef, $u->id, $sid, nfreeze($optref) );
        return $class->SUPER::new( $u, $sid );
    }

    # we failed somewhere
    return undef;
}

sub arg_list {
    return ("Import status id");
}

sub is_common { 1 }

sub is_visible { 1 }

sub is_significant { 1 }

sub always_checked { 1 }

sub subscription_as_html {
    my ( $class, $subscr ) = @_;
    return LJ::Lang::ml('event.xpost.failure');
}

sub content {
    my $self = $_[0];

    if ( $self->account ) {
        return LJ::Lang::ml(
            'event.xpost.failure.content',
            {
                accountname => $self->account->displayname,
                errmsg      => $self->errmsg,
            }
        );

    }
    else {
        return LJ::Lang::ml('event.xpost.noaccount');
    }
}

# short enough that we can just use this the normal content as the summary
sub content_summary {
    return $_[0]->content(@_);
}

# contents for plaintext email
sub as_email_string {
    my $self    = $_[0];
    my $subject = '"' . $self->entry->subject_text . '"';
    $subject = LJ::Lang::ml('event.xpost.nosubject') unless defined $subject;

    return LJ::Lang::ml(
        'event.xpost.email.body.text.failure',
        {
            accountname => $self->account->displayname,
            entrydesc   => $subject,
            entryurl    => $self->entry->url,
            errmsg      => $self->errmsg,
        }
    ) . "\n\n";
}

sub as_email_html {
    my $self    = $_[0];
    my $subject = $self->entry->subject_html;
    $subject = LJ::Lang::ml('event.xpost.nosubject') unless defined $subject;

    return LJ::Lang::ml(
        'event.xpost.email.body.html.failure',
        {
            accountname => $self->account->displayname,
            entrydesc   => $subject,
            entryurl    => $self->entry->url,
            errmsg      => $self->errmsg,
        }
    ) . "\n\n";
}

sub as_email_subject {
    my $self    = $_[0];
    my $journal = $self->u ? $self->u->user : LJ::Lang::ml('error.nojournal');

    return LJ::Lang::ml(
        'event.xpost.email.subject.failure',
        {
            sitenameshort => $LJ::SITENAMESHORT,
            username      => $journal,
        }
    );
}

# the main title for the event
sub as_string {
    my $self = $_[0];
    my $subject =
          $self->entry->subject_html
        ? $self->entry->subject_html
        : LJ::Lang::ml('event.xpost.nosubject');

    if ( $self->account ) {
        return LJ::Lang::ml(
            'event.xpost.failure.title',
            {
                accountname => $self->account->displayname,
                entrydesc   => $subject,
                entryurl    => $self->entry->url
            }
        );

    }
    else {
        return LJ::Lang::ml('event.xpost.noaccount');
    }
}

# available for all personal users.
sub available_for_user {
    my ( $class, $u, $subscr ) = @_;
    return $u->is_personal ? 1 : 0,;
}

# override parent class subscriptions method to always return
# a subscription object for the user
sub raw_subscriptions {
    my ( $class, $self, %args ) = @_;

    $args{ntypeid} = LJ::NotificationMethod::Inbox->ntypeid;    # Inbox

    return $class->_raw_always_subscribed( $self, %args );
}

sub get_subscriptions {
    my ( $self, $u, $subid ) = @_;

    unless ($subid) {
        my $row = {
            userid  => $u->{userid},
            ntypeid => LJ::NotificationMethod::Inbox->ntypeid,    # Inbox
        };

        return LJ::Subscription->new_from_row($row);
    }

    return $self->SUPER::get_subscriptions( $u, $subid );
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

    my $u    = $self->u;
    my $item = $u->selectrow_array(
        'SELECT status FROM import_status WHERE userid = ? AND import_status_id = ?',
        undef, $u->id, $self->arg1 );
    return undef
        if $u->err || !$item;

    return $self->{_optsref} = thaw($item);
}

1;
