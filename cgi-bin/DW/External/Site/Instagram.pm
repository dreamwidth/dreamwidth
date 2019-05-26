#!/usr/bin/perl
#
# DW::External::Site::Instagram
#
# Class to support linking to user accounts on Instagram.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::External::Site::Instagram;

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
# returns URL to this account's page
sub journal_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    return 'https://' . $self->{hostname} . "/" . $u->user;
}

# argument: DW::External::User
# returns URL to this account's profile
sub profile_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    return 'https://' . $self->{hostname} . "/" . $u->user;
}

# argument: DW::External::User
# returns info for the badge image (userhead icon) for this user
sub badge_image {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    return {
        url    => "$LJ::IMGPREFIX/profile_icons/instagram.png",
        width  => 16,
        height => 16,
    };
}

# returns a cleaned version of the username
sub canonical_username {
    my $input = $_[1];
    my $user  = "";

    if ( $input =~ /^\s*([a-zA-Z0-9_.]+)\s*$/ ) {    # good username
        $user = $1;
    }
    return $user;
}

1;
