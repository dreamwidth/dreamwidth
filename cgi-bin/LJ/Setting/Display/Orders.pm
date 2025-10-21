#!/usr/bin/perl
#
# LJ::Setting::Display::Orders - shows a link to the user's payment history page
#
# Authors:
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package LJ::Setting::Display::Orders;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return $u && !$u->is_community ? 1 : 0;
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.orders.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    return
        "<a href='$LJ::SITEROOT/shop/history'>"
        . $class->ml('setting.display.orders.option') . "</a>";
}

1;
