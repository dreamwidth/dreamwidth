#!/usr/bin/perl
#
# DW::Setting::CommunityPromo
#
# DW::Setting module for choosing whether a community should appear on the list of
# promoted communities, on account creation
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::CommunityPromo;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return $u->is_community;
}

sub label {
    my $class = $_[0];

    return $class->ml('setting.communitypromo.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $communitypromo = $class->get_arg( $args, 'communitypromo' ) || $u->optout_community_promo;

    my $ret = LJ::html_check(
        {
            name     => "${key}communitypromo",
            id       => "${key}communitypromo",
            value    => 1,
            selected => $communitypromo,
        }
    );
    $ret .= " <label for='${key}communitypromo'>";
    $ret .= $class->ml('setting.communitypromo.option');
    $ret .= "</label>";

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    $u->optout_community_promo( $class->get_arg( $args, "communitypromo" ) ? "1" : "0" );

    return 1;
}

1;
