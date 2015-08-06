#!/usr/bin/perl
#
# DW::External::Site::LJRossia
#
# Class to support the lj.rossia.com site, based on DW::External::Site::LiveJournal
#
# Authors:
#      Adam Bernard <https://pseudomonas.dreamwidth.org>
#
# Copyright (c) 2009/2015 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::External::Site::LJRossia;

use strict;
use base 'DW::External::Site';
use Carp qw/ croak /;


# new does nothing for these classes
sub new { croak 'cannot build with new'; }


# returns 1/0 if we allow this domain
sub accepts {
    my ( $class, $parts ) = @_;

    # allows anything at lj.rossia.org
    return 0 unless $parts->[-1] eq 'org'    &&
                    $parts->[-2] eq 'rossia' &&
                    $parts->[-3] eq 'lj';

    return bless { hostname => 'lj.rossia.org' }, $class;
}


# argument: DW::External::User
# returns URL to this account's journal
sub journal_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    my $user = $u->user;
    return "http://lj.rossia.org/users/$user/";
}

sub profile_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

	my $user = $u->user;
    return "http://lj.rossia.org/userinfo.bml?user=$user";
	
}


# argument: DW::External::User
# returns info for the badge image (head icon) for this user
sub badge_image {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    my $type = $self->journaltype( $u ) || 'P';
    my $gif = {
               P => [ '/external/ljr-userinfo.gif',   17, 17 ],
               C => [ '/external/ljr-community.gif',  16, 16 ],
               Y => [ '/external/ljr-syndicated.gif', 16, 16 ],
              };

    my $img = $gif->{$type};
    return {
        url     => $LJ::IMGPREFIX . $img->[0],
        width   => $img->[1],
        height  => $img->[2],
    }
}

1;
