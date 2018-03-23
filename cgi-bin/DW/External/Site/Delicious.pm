#!/usr/bin/perl
#
# DW::External::Site::Delicious
#
# Class to support Delicious linking.
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

package DW::External::Site::Delicious;

use strict;
use base 'DW::External::Site';
use Carp qw/ croak /;


# new does nothing for these classes
sub new { croak 'cannot build with new'; }


# returns 1/0 if we allow this domain
sub accepts {
    my ( $class, $parts ) = @_;

    # allows anything at del.icio.us
    return 0 unless $parts->[-1] eq 'us'    &&
                    $parts->[-2] eq 'icio'  &&
                    $parts->[-3] eq 'del';

    return bless { hostname => 'del.icio.us' }, $class;
}


# argument: DW::External::User
# returns URL to this account's bookmarks
sub journal_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    return 'http://' . $self->{hostname} . '/' . $u->user;
}


# argument: DW::External::User
# returns URL to this account's stacks list
sub profile_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    return 'http://' . $self->{hostname} . '/stacks/' . $u->user;
}


# argument: DW::External::User
# returns info for the badge image (userhead icon) for this user
sub badge_image {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    # for lack of anything better, let's use the favicon
    return {
        url     => "https://del.icio.us/favicon.ico",
        width   => 16,
        height  => 16,
    }
}


1;
