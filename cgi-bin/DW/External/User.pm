#!/usr/bin/perl
#
# DW::External::User
#
# Represents a user from an external site.  Note that we can't actually
# do much with such users.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::External::User;

use strict;
use Carp qw/ croak /;
use DW::External::Site;


# given a site (url) and a user (string), construct an external
# user to return; undef on error
sub new {
    my ( $class, %opts ) = @_;

    my $site = delete $opts{site} or return undef;
    my $user = delete $opts{user} or return undef;
    croak 'unknown extra options'
        if %opts;

    # site is required, or bail
    my $ext = DW::External::Site->new( site => $site )
        or return undef;

    my $self = {
        user => $user,
        site => $ext,
    };

    return bless $self, $class;
}


# return our username
sub user {
    return $_[0]->{user};
}


# return our external site
sub site {
    return $_[0]->{site};
}


# return the ljuser_display block
sub ljuser_display {
    my $self = $_[0];

    my $user = $self->user;
    my $profile_url = $self->site->profile_url( $self );
    my $journal_url = $self->site->journal_url( $self );
    my $badge_image_url = $self->site->badge_image_url( $self );

    return "<span class='ljuser' lj:user='$user' style='white-space: nowrap;'><a href='$profile_url'>" .
           "<img src='$badge_image_url' alt='[info]' style='vertical-align: bottom; border: 0; padding-right: 1px;' />" .
           "</a><a href='$journal_url'><b>$user</b></a></span>";
}


1;
