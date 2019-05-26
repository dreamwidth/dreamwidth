#!/usr/bin/perl
#
# DW::External::Site::LastFM
#
# Class to support the Last.fm site.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Denise Paolucci <denise@dreamwidth.org>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::External::Site::LastFM;

use strict;
use base 'DW::External::Site';
use Carp qw/ croak /;

# new does nothing for these classes
sub new { croak 'cannot build with new'; }

# returns an object if we allow this domain; else undef
sub accepts {
    my ( $class, $parts ) = @_;

    # let's just assume the last two parts are good if we have them
    return undef unless scalar(@$parts) >= 2;

    return bless { hostname => "$parts->[-2].$parts->[-1]" }, $class;
}

# argument: DW::External::User
# returns URL to this account's main dashboard
sub journal_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    return 'http://' . $self->{hostname} . '/user/' . $u->user;
}

# argument: DW::External::User
# returns URL to this account's stacks list
sub profile_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    return 'http://' . $self->{hostname} . '/user/' . $u->user . '/charts';
}

# argument: DW::External::User
# returns info for the badge image (userhead icon) for this user
sub badge_image {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    # for lack of anything better, let's use the favicon
    return {
        url    => "http://cdn.last.fm/flatness/favicon.2.ico",
        width  => 16,
        height => 16,
    };
}

1;
