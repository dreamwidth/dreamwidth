#!/usr/bin/perl
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package LJ::Event::CommunityModeratedEntryNew;

use strict;
use DW::Entry::Moderated;
use Carp qw(croak);
use base 'LJ::Event';

=head1 NAME

LJ::Event::CommunityModeratedEntryNew - Event for administrators when their entry is a community

=cut

sub new {
    my ( $class, $u, $comm, $modid ) = @_;

    foreach ( $u, $comm ) {
        LJ::errobj( 'Event::CommunityModeratedEntryNew', u => $_ )->throw unless LJ::isu( $_ );
    }

    return $class->SUPER::new( $u, $comm->userid, $modid );
}

sub arg_list {
    return ( "Comm userid", "Moderated entry id" );
}

sub is_common { 0 }

sub comm {
    my $self = $_[0];
    return LJ::load_userid( $self->arg1 );
}

sub moderated_entry {
    my $self = $_[0];
    return DW::Entry::Moderated->new( $self->comm, $self->arg2 );
}

sub as_html {
    my $self = shift;
    return sprintf( "A new moderated entry <a href='%s'>has been submitted</a> to %s.",
                    $self->comm->moderation_queue_url( $self->moderated_entry->id ), $self->comm->ljuser_display );
}

sub as_html_actions {
    my ( $self ) = @_;

    my $moderated_entry = $self->moderated_entry;
    my $comm = $self->comm;

    my $ret .= "<div class='actions'>";
    $ret .= " <a href='" . $comm->moderation_queue_url( $moderated_entry->id ) . "'>View Entry</a> |";
    $ret .= " <a href='" . $comm->moderation_queue_url. "'>View Moderation Queue</a>";
    $ret .= "</div>";

    return $ret;
}

sub content {
    my ( $self, $target ) = @_;

    my $moderated_entry = $self->moderated_entry;

    my $ret = "<ul>";
    $ret .= "<li>Poster: " . $moderated_entry->poster->ljuser_display . "</li>",
    $ret .= "<li>Subject: " . $moderated_entry->subject . "</li>";
    $ret .= "</ul>";

    return $ret . $self->as_html_actions;
}

sub as_string {
    my $self = shift;
    return sprintf( "A new moderated entry has been submitted to %s (%s).",
                    $self->comm->username, $self->comm->moderation_queue_url( $self->moderated_entry->id ) );
}

my @_ml_strings_en = (
    'esn.moderated_submission.subject2',
    'esn.moderated_submission.body2',
    'esn.moderated_submission.entry',
    'esn.moderated_submission.queue',
);

sub as_email_subject {
    my ( $self, $u ) = @_;

    return LJ::Lang::get_text( $u->prop( 'browselang' ), 'esn.moderated_submission.subject2', undef,
        {
            community => $self->comm->username,
        });
}

sub _as_email {
    my ( $self, $u, $is_html ) = @_;


    my $moderated_entry = $self->moderated_entry;
    my $comm            = $self->comm;
    my $lang            = $u->prop( 'browselang' );

    # Precache text
    LJ::Lang::get_text_multi( $lang, undef, \@_ml_strings_en );

    my $format_username = sub { return $is_html ? $_[0]->ljuser_display : $_[0]->display_username };
    return LJ::Lang::get_text( $lang, 'esn.moderated_submission.body2', undef, {
                user        => $format_username->( $moderated_entry->poster ),
                community   => $format_username->( $self->comm ),
                subject     => $moderated_entry->subject,
    } ) . $self->format_options( $is_html, $lang, {},
        {
            'esn.moderated_submission.entry'    => [ 1, $comm->moderation_queue_url( $moderated_entry->id ) ],
            'esn.moderated_submission.queue'    => [ 2, $comm->moderation_queue_url ],
        }
    );
}

sub as_email_string {
    my ( $self, $u ) = @_;
    return _as_email( $self, $u, 0 );
}

sub as_email_html {
    my ( $self, $u ) = @_;
    return _as_email( $self, $u, 1 );
}

sub subscription_as_html {
    my ( $class, $subscr ) = @_;
    return LJ::Lang::ml( 'event.community_moderated_entry_new' );
}

sub available_for_user {
    my ($class, $u, $subscr) = @_;

    return $u->is_identity ? 0 : 1;
}

package LJ::Error::Event::CommunityModeratedEntryNew;
sub fields { 'u' }
sub as_string {
    my $self = shift;
    return "LJ::Event::CommunityModeratedEntryNew passed bogus u object: $self->{u}";
}

1;
