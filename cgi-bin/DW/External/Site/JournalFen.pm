#!/usr/bin/perl
#
# DW::External::Site::JournalFen
#
# Class to support the Journalfen.net site.
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

package DW::External::Site::JournalFen;

use strict;
use base 'DW::External::Site';
use Carp qw/ croak /;

# new does nothing for these classes
sub new { croak 'cannot build with new'; }

# returns 1/0 if we allow this domain
sub accepts {
    my ( $class, $parts ) = @_;

    # allows anything at journalfen.net
    return 0
        unless $parts->[-1] eq 'net'
        && $parts->[-2] eq 'journalfen';

    return bless { hostname => 'journalfen.net' }, $class;
}

sub badge_image {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    return {
        url    => $LJ::IMGPREFIX."/silk/identity/user_other.png",
        width  => 16,
        height => 16,
    };
}

sub canonical_username {
    return LJ::canonical_username( $_[1] );
}

1;
