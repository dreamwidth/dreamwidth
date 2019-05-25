#!/usr/bin/perl
#
# DW::External::Site::LiveJournal
#
# Class to support the LiveJournal.com site.
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

package DW::External::Site::LiveJournal;

use strict;
use base 'DW::External::Site';
use Carp qw/ croak /;

# new does nothing for these classes
sub new { croak 'cannot build with new'; }

# returns 1/0 if we allow this domain
sub accepts {
    my ( $class, $parts ) = @_;

    # allows anything at livejournal.com
    return 0
        unless $parts->[-1] eq 'com'
        && $parts->[-2] eq 'livejournal';

    return bless { hostname => 'livejournal.com' }, $class;
}

# argument: DW::External::User
# returns URL to this account's journal
sub journal_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

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

    my $type = $self->journaltype($u) || 'P';
    my $gif  = {
        P => [ '/external/lj-userinfo.gif',   17, 17 ],
        C => [ '/external/lj-community.gif',  16, 16 ],
        Y => [ '/external/lj-syndicated.gif', 16, 16 ],
    };

    my $img = $gif->{$type};
    return {
        url    => $LJ::IMGPREFIX . $img->[0],
        width  => $img->[1],
        height => $img->[2],
    };
}

sub canonical_username {
    return LJ::canonical_username( $_[1] );
}

1;
