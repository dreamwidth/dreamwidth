#!/usr/bin/perl
#
# DW::External::Site::Unknown
#
# Class to try supporting some unknown site.
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

package DW::External::Site::Unknown;

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
# returns URL to this account's journal
sub journal_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    return 'http://www.' . $self->{hostname} . '/users/' . $u->user . '/';
}

# argument: DW::External::User
# returns info for the badge image (head icon) for this user
sub badge_image {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    # since we don't know what site this is, they can have an "unknown" icon
    return {
        url    => "$LJ::IMGPREFIX/silk/identity/user_other.png",
        width  => 16,
        height => 16,
    };
}

1;
