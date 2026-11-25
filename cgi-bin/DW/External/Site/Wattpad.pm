#!/usr/bin/perl
#
# DW::External::Site::Wattpad
#
# Class to support Wattpad user linking.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::External::Site::Wattpad;

use strict;
use base 'DW::External::Site';
use Carp qw/ croak /;

sub new { croak 'cannot build with new'; }

sub journal_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    return 'https://' . $self->{hostname} . '/user/' . $u->user;
}

# The account and profile links use the same page on this service.
sub profile_url {
    my ( $self, $u ) = @_;
    return $self->journal_url($u);
}

sub badge_image {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    return {
        url    => "$LJ::IMGPREFIX/profile_icons/wattpad.png",
        width  => 16,
        height => 16,
    };
}

1;
