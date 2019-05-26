#!/usr/bin/perl
#
# LJ::Event::RemovedFromCircle
#
# This is the event that's fired when someone removes another user from their circle.
#
# Authors:
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package LJ::Event::RemovedFromCircle;

use strict;
use Scalar::Util qw( blessed );
use Carp qw( croak );
use base 'LJ::Event';

sub new {
    my ( $class, $u, $fromu, $actionid ) = @_;

    foreach ( $u, $fromu ) {
        croak 'Not an LJ::User' unless blessed $_ && $_->isa("LJ::User");
    }

    croak 'Invalid actionid; must be 1 (trust) or 2 (watch)'
        unless $actionid == 1 || $actionid == 2;

    return $class->SUPER::new( $u, $fromu->id, $actionid );
}

sub arg_list {
    return ( "From userid", "Action (1=T,2=W)" );
}

sub is_common { 0 }

my @_ml_strings_en = qw(
    esn.removedfromcircle.trusted.subject
    esn.removedfromcircle.watched.subject
    esn.removedfromcircle.trusted.email_text
    esn.removedfromcircle.watched.email_text
    esn.remove_trust
    esn.remove_watch
    esn.post_entry
    esn.edit_friends
    esn.edit_groups
);

sub as_email_subject {
    my ( $self, $u ) = @_;

    my $str =
        $self->trusted
        ? 'esn.removedfromcircle.trusted.subject'
        : 'esn.removedfromcircle.watched.subject';

    return LJ::Lang::get_default_text( $str, { who => $self->fromuser->display_username } );
}

sub _as_email {
    my ( $self, $u, $is_html ) = @_;

    my $user = $is_html ? $u->ljuser_display : $u->display_username;
    my $poster = $is_html ? $self->fromuser->ljuser_display : $self->fromuser->display_username;
    my $postername      = $self->fromuser->user;
    my $journal_url     = $self->fromuser->journal_base;
    my $journal_profile = $self->fromuser->profile_url;

    # Precache text lines
    LJ::Lang::get_default_text_multi( \@_ml_strings_en );

    my $vars = {
        who        => $self->fromuser->display_username,
        poster     => $poster,
        postername => $poster,
        journal    => $poster,
        user       => $user,
    };

    if ( $self->trusted ) {
        return LJ::Lang::get_default_text( 'esn.removedfromcircle.trusted.email_text', $vars )
            . $self->format_options(
            $is_html, undef, $vars,
            {
                'esn.remove_trust' => [
                    !$u->trusts( $self->fromuser ) ? 0 : 1,
                    "$LJ::SITEROOT/circle/$postername/edit"
                ],
                'esn.post_entry'   => [ 2, "$LJ::SITEROOT/update" ],
                'esn.edit_friends' => [ 3, "$LJ::SITEROOT/manage/circle/edit" ],
                'esn.edit_groups'  => [ 4, "$LJ::SITEROOT/manage/circle/editfilters" ],
            }
            );
    }
    else {    # watched
        return LJ::Lang::get_default_text( 'esn.removedfromcircle.watched.email_text', $vars )
            . $self->format_options(
            $is_html, undef, $vars,
            {
                'esn.remove_watch' => [
                    !$u->watches( $self->fromuser ) ? 0 : 1,
                    "$LJ::SITEROOT/circle/$postername/edit"
                ],
                'esn.post_entry'   => [ 2, "$LJ::SITEROOT/update" ],
                'esn.edit_friends' => [ 3, "$LJ::SITEROOT/manage/circle/edit" ],
                'esn.edit_groups'  => [ 4, "$LJ::SITEROOT/manage/circle/editfilters" ],
            }
            );
    }
}

sub as_email_string {
    my ( $self, $u ) = @_;
    return _as_email( $self, $u, 0 );
}

sub as_email_html {
    my ( $self, $u ) = @_;
    return _as_email( $self, $u, 1 );
}

sub fromuser {
    my $self = shift;
    return LJ::load_userid( $self->arg1 );
}

sub actionid {
    my $self = shift;
    return $self->arg2;
}

sub trusted {
    my $self = shift;
    return $self->actionid == 1 ? 1 : 0;
}

sub watched {
    my $self = shift;
    return $self->actionid == 2 ? 1 : 0;
}

sub as_html {
    my $self = shift;

    if ( $self->trusted ) {
        return sprintf( "%s has removed your access to their journal.",
            $self->fromuser->ljuser_display );
    }
    else {    # watched
        return sprintf( "%s has unsubscribed from your journal.", $self->fromuser->ljuser_display );
    }
}

sub as_html_actions {
    my ($self) = @_;

    my $u        = $self->u;
    my $fromuser = $self->fromuser;

    my $ret .= "<div class='actions'>";
    if ( $self->trusted ) {
        $ret .= "<a href='$LJ::SITEROOT/circle/" . $fromuser->user . "/edit'>Remove Access</a> |"
            if $u->trusts($fromuser);
        $ret .= " <a href='" . $fromuser->profile_url . "'>View Profile</a>";
    }
    else {    # watched
        $ret .= "<a href='$LJ::SITEROOT/circle/" . $fromuser->user . "/edit'>Unsubscribe</a> |"
            if $u->watches($fromuser);
        $ret .= " <a href='" . $fromuser->profile_url . "'>View Profile</a>";
    }
    $ret .= "</div>";

    return $ret;
}

sub as_string {
    my $self = shift;

    if ( $self->trusted ) {
        return sprintf( "%s has removed your access to their journal.", $self->fromuser->user );
    }
    else {    # watched
        return sprintf( "%s has unsubscribed from your journal.", $self->fromuser->user );
    }
}

sub subscription_as_html {
    my ( $class, $subscr ) = @_;
    my $journal          = $subscr->journal or croak "No user";
    my $journal_is_owner = $journal->equals( $subscr->owner );

    if ($journal_is_owner) {
        return BML::ml('event.removedfromcircle.me');    # "Someone removes me from their circle";
    }
    else {
        my $user = $journal->ljuser_display;
        return BML::ml( 'event.removedfromcircle.user', { user => $user } )
            ;    # "Someone removes $user from their circle";
    }
}

# only users with the track_defriended cap can use this
sub available_for_user {
    my ( $class, $u, $subscr ) = @_;
    return $u->can_track_defriending;
}

sub content {
    my ( $self, $target ) = @_;
    return $self->as_html_actions;
}

1;
