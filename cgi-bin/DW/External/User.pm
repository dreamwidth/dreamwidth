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
use LJ::CleanHTML;


# given a site (url) and a user (string), construct an external
# user to return; undef on error
sub new {
    my ( $class, %opts ) = @_;

    my $site = delete $opts{site} or return undef;
    my $user = delete $opts{user} or return undef;
    croak 'unknown extra options'
        if %opts;

    # site is required, or bail
    my $ext = DW::External::Site->get_site( site => $site )
        or return undef;

    my $vuser = $ext->canonical_username( $user )
        or return undef;

    my $self = {
        user => $vuser,
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
    my ( $self, %opts ) = @_;

    my $user = $self->user;
    my $profile_url = $self->site->profile_url( $self );
    my $journal_url = $self->site->journal_url( $self );
    my $badge_image = $self->site->badge_image( $self );
    $badge_image->{url} = LJ::CleanHTML::https_url( $badge_image->{url} ) if $LJ::IS_SSL;
    my $display_class = $opts{no_ljuser_class} ? "" : " class='ljuser'";
    my $domain = $self->site->{domain} ? $self->site->{domain} : $self->site->{hostname};

    return "<span style='white-space: nowrap;'$display_class><a href='$profile_url'>" .
           "<img src='$badge_image->{url}' alt='[$domain profile] ' style='vertical-align: bottom; border: 0; padding-right: 1px;' width='$badge_image->{width}' height='$badge_image->{height}'/>" .
           "</a><a href='$journal_url'><b>$user</b></a></span>";
}


1;
