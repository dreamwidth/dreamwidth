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

sub arg_list {
    return ( "Ext. account id", "Entry ditemid" );
}

sub is_common { 0 }

sub is_visible { 1 }

sub is_significant { 1 }

sub always_checked { 0 }

sub subscription_as_html {
    my ( $class, $subscr ) = @_;
    return LJ::Lang::ml('event.xpost.success');
}

# FIXME make this more useful, like include a link to the crosspost
sub content {
    my ($self) = @_;
    if ( $self->account ) {
        return LJ::Lang::ml( 'event.xpost.success.content',
            { accountname => $self->account->displayname } );
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
        'event.xpost.email.body.text.success',
        {
            accountname => $self->account->displayname,
            entrydesc   => $subject,
            entryurl    => $self->entry->url,
        }
    ) . "\n\n";
}

sub as_email_html {
    my $self    = $_[0];
    my $subject = $self->entry->subject_html;
    $subject = LJ::Lang::ml('event.xpost.nosubject') unless defined $subject;

    return LJ::Lang::ml(
        'event.xpost.email.body.html.success',
        {
            accountname => $self->account->displayname,
            entrydesc   => $subject,
            entryurl    => $self->entry->url,
        }
    ) . "\n\n";
}

sub as_email_subject {
    my $self    = $_[0];
    my $journal = $self->u ? $self->u->user : LJ::Lang::ml('error.nojournal');

    return LJ::Lang::ml(
        'event.xpost.email.subject.success',
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
            'event.xpost.success.title',
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
    $_[0]->{account} = DW::External::Account->get_external_account( $self->u, $self->acctid );
    return $_[0]->{account};
}

# the entry crossposted
sub entry {
    my ($self) = @_;
    return $self->{entry} if $self->{entry};
    $_[0]->{entry} = LJ::Entry->new( $self->u, ( ditemid => $self->ditemid ) );
    return $self->{entry};
}

1;
