#!/usr/bin/perl
#
# DW::Setting::Display::OpenIDClaim - Shows a link to claim an OpenID account
#
# Authors:
#      Randomling
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Setting::Display::OpenIDClaim;
use base 'LJ::Setting';
use strict;

sub should_render {
    my ( $class, $u ) = @_;

    return $u && !$u->is_community ? 1 : 0;
}

sub label {
    my ($class) = @_;

    return $class->ml('setting.display.openidclaim.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    return
        "<a href='$LJ::SITEROOT/openid/claim'>"
        . $class->ml('setting.display.openidclaim.option') . "</a>";
}

1;
