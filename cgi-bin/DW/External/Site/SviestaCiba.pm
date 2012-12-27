#!/usr/bin/perl
#
# DW::External::Site::SviestaCiba
#
# Class to support the klab.lv site. (fork from DeadJournal implementation)
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Kristaps Karlsons <kristaps.karlsons@gmail.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::External::Site::SviestaCiba;

use strict;
use base 'DW::External::Site';
use Carp qw/ croak /;


# new does nothing for these classes
sub new { croak 'cannot build with new'; }


# returns 1/0 if we allow this domain
sub accepts {
    my ( $class, $parts ) = @_;

    # allows anything at klab.lv
    return 0 unless $parts->[-1] eq 'lv' &&
                    $parts->[-2] eq 'klab';

    return bless { hostname => 'klab.lv' }, $class;
}


# argument: DW::External::User
# returns URL to the badge image (head icon) for this user
sub badge_image_url {
    my ( $self, $u ) = @_;
    croak 'need a DW::External::User'
        unless $u && ref $u eq 'DW::External::User';

    my $type = $self->journaltype( $u ) || 'P';
    my $gif = {
               P => '/external/lj-userinfo.gif',
               C => '/external/lj-community.gif',
               Y => '/external/lj-syndicated.gif',
              };
    return $LJ::IMGPREFIX . $gif->{$type};
}


# argument: request hash
# returns: modified request hash
sub pre_crosspost_hook {
    my ( $self, $req ) = @_;

    # avoid "unknown metadata" error
    delete $req->{props}->{useragent};
    delete $req->{props}->{adult_content};
    delete $req->{props}->{current_location};

    delete $req->{props}->{used_rte};

    return $req;
}

sub canonical_username {
    return LJ::canonical_username( $_[1] );
}

1;
