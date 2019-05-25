#!/usr/bin/perl
#
# DW::External::Site::Inksome
#
# Class to support the Inksome.com site.
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

package DW::External::Site::Inksome;

use strict;
use base 'DW::External::Site';
use Carp qw/ croak /;

# new does nothing for these classes
sub new { croak 'cannot build with new'; }

# returns 1/0 if we allow this domain
sub accepts {
    my ( $class, $parts ) = @_;

    # allows anything at inksome.com
    return 0
        unless $parts->[-1] eq 'com'
        && $parts->[-2] eq 'inksome';

    return bless { hostname => 'inksome.com' }, $class;
}

# argument: DW::External::User
# returns URL to this account's journal
sub journal_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    # normal default is broken for Inksome community redirect
    my $user = $u->user;
    $user =~ tr/_/-/;
    return "http://$user.$self->{domain}/";
}

# argument: DW::External::User
# returns info for the badge image (head icon) for this user
sub badge_image {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    # Inksome went away, so just assume every account is personal
    return {
        url    => "$LJ::IMGPREFIX/external/ink-userinfo.gif",
        width  => 17,
        height => 17,
    };
}

1;
