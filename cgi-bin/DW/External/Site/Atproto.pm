#!/usr/bin/perl
#
# DW::External::Site::Bluesky
#
# Support class for elements shared between atproto-based sites. Links to
# aturi.to to provide a whole-account overview for atproto..
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

package DW::External::Site::Atproto;

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

    # we don't currently expose a way to reference "an atproto account" which
    # may or may not have a bluesky profile or other services attached. But
    # sending the user to aturi is the correct way to handle that since it
    # presents the well-known sites the account DOES have a profile on in and
    # end-user friendly way.
    return 'http://aturi.to/' . $u->user;
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
        url    => "https://atproto.com/en/icon.ico",
        width  => 16,
        height => 16,
    };
}

# Bluesky/atproto has somewhat unique username rules because usernames must be
# FQDNs. It is also expected that usernames be canonicalized to lowercase, as
# per https://atproto.com/specs/handle. This doesn't fully validate usernames,
# but it will reject anything blatantly wrong (in particular, it does not check
# the length of the segments... I think everything else is in here?).
#
# TODO: Should this also accept raw DIDs?
sub canonical_username {
    my $input = $_[1];
    my $user  = "";

    if (
        $input =~ m/
            ^\s*
            ((?:(?:[a-z0-9][a-z0-9\-]*)?[a-z0-9]\.)+
                [a-z](?:[a-z0-9\-]*[a-z0-9])?)
            \s*$
        /ix
        )
    {
        $user = lc $1;
    }
    return $user;
}

1;
