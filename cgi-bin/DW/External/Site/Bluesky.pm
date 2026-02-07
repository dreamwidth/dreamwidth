#!/usr/bin/perl
#
# DW::External::Site::Bluesky
#
# Class to support Bluesky linking.
#
# Authors:
#      Joshua Barrett <jjbarr@ptnote.dev>
#
# Copyright (c) 2026 by Dreamwidth Studios LLC.
#
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself. For a copy of the
# license, please reference 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::External::Site::Bluesky;

use strict;
use base 'DW::External::Site::Atproto';
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

    return 'http://' . $self->{hostname} . '/profile/' . $u->user;
}

# argument: DW::External::User
# returns URL to this account's journal
sub profile_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    return $self->journal_url($u);
}

# argument: DW::External::User
# returns info for the badge image (head icon) for this user
sub badge_image {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    # for lack of anything better, let's use the favicon
    return {
        url    => "https://web-cdn.bsky.app/static/favicon-16x16.png",
        width  => 16,
        height => 16,
    };
}

1;

