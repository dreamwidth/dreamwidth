#!/usr/bin/perl
#
# DW::External::Site::ArchiveofOurOwn
#
# Class to support the ArchiveofOurOwn.org (AO3) site.
#
# Authors:
#      Allyson Sgro <allyson@chemicallace.com>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::External::Site::ArchiveofOurOwn;

use strict;
use base 'DW::External::Site';
use Carp qw/ croak /;

# new does nothing for these classes
sub new { croak 'cannot build with new'; }

# returns 1/0 if we allow this domain
sub accepts {
    my ( $class, $parts ) = @_;

    # allows anything at archiveofourown.org and ao3.org
    return 0
        unless $parts->[-1] eq 'org'
        && ( $parts->[-2] eq 'archiveofourown'
        || $parts->[-2] eq 'ao3' );

    return bless { hostname => 'archiveofourown.org' }, $class;
}

# argument: DW::External::User
# returns info for the to the badge image (head icon) for this user
sub badge_image {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    return {
        url    => 'http://archiveofourown.org/favicon.ico',
        width  => 16,
        height => 16,
    };
}

1;
