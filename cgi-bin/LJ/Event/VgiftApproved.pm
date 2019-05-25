#!/usr/bin/perl
#
# LJ::Event::VgiftApproved
#
# Event for approving a virtual gift
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package LJ::Event::VgiftApproved;
use strict;
use base 'LJ::Event';
use Carp qw(croak);
use DW::VirtualGift;

sub new {
    my ( $class, $u, $fromu, $vgift ) = @_;

    croak 'Not to an LJ::User'   unless LJ::isu($u);
    croak 'Not from an LJ::User' unless LJ::isu($fromu);

    $vgift = DW::VirtualGift->new($vgift) unless ref $vgift;
    croak 'Invalid vgift' unless $vgift && $vgift->name;

    return $class->SUPER::new( $u, $fromu->id, $vgift->id );
}

sub arg_list {
    return ( "From userid", "Vgift id" );
}

# access args
sub fromuid { return $_[0]->arg1 }

sub vgiftid { return $_[0]->arg2 }

sub fromu {
    my ($self) = @_;
    $self->{fromu} = LJ::load_userid( $self->fromuid )
        unless $self->{fromu};
    return $self->{fromu};
}

sub vgift {
    my ($self) = @_;
    $self->{vgift} = DW::VirtualGift->new( $self->vgiftid )
        unless $self->{vgift};
    return $self->{vgift};
}

# message content
sub _summary {
    my ( $self, $admin ) = @_;
    return BML::ml('event.vgift.notfound')
        unless $self->vgift && $self->vgift->name;
    my $yn = $self->vgift->approved;

    # event.vgift.approved.content.Y = thumbs up
    # event.vgift.approved.content.N = thumbs down
    return BML::ml(
        "event.vgift.approved.content.$yn",
        {
            vgift => $self->vgift->name_ehtml,
            admin => $admin
        }
    );
}

sub as_string { return $_[0]->_summary( $_[0]->fromu->display_username ) }

sub as_html { return $_[0]->_summary( $_[0]->fromu->ljuser_display ) }

sub as_html_actions {
    my ($self) = @_;
    my $url    = "$LJ::SITEROOT/admin/vgifts/?mode=view&id=" . $self->vgiftid;
    my $ret    = "<div class='actions'>";
    $ret .= BML::ml( 'event.vgift.approved.actions', { aopts => "href='$url'" } );
    $ret .= "</div>\n";

    return $ret;
}

sub content_summary { return $_[0]->as_html }

sub content {
    my ($self) = @_;
    return BML::ml('event.vgift.notfound')
        unless $self->vgift && $self->vgift->name;
    my $yn  = $self->vgift->approved;
    my $ret = '<p>';
    $ret .=
        BML::ml( "event.vgift.approved.msg.$yn", { vgift => $self->vgift->name_ehtml } ) . '</p>';
    if ( $self->vgift && $self->vgift->approved_why ) {
        my $reason = LJ::ehtml( $self->vgift->approved_why );
        my $mltext =
            BML::ml( 'event.vgift.approved.reason', { admin => $self->fromu->ljuser_display } );
        $ret .= "<p>$mltext</p><p><q>$reason</q></p>\n";
    }
    $ret .= $self->as_html_actions;

    return $ret;
}

# subscriptions are always on, can't be turned off
sub is_common { 1 }

sub is_visible { 0 }

sub always_checked { 1 }

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

1;
