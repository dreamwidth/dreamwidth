#!/usr/bin/perl
#
# DW::Setting::RandomPaidGifts
#
# DW::Setting module for choosing whether you can appear as a choice when others
# are looking for a random free user to give a paid account to.
#
# Authors:
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::RandomPaidGifts;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return $u->is_perm || $u->is_identity ? 0 : 1;
}

sub label {
    my $class = $_[0];

    return $class->ml('setting.randompaidgifts.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $iscomm = $u->is_community ? '.comm' : '';

    my $randompaidgifts =
        $class->get_arg( $args, "randompaidgifts" ) || $u->prop("opt_randompaidgifts") || 'Y';

    my $ret = LJ::html_check(
        {
            name     => "${key}randompaidgifts",
            id       => "${key}randompaidgifts",
            value    => 1,
            selected => $randompaidgifts eq 'N' ? 0 : 1,
        }
    );
    $ret .= " <label for='${key}randompaidgifts'>";
    $ret .=
          $u->is_paid
        ? $class->ml("setting.randompaidgifts.option.paid$iscomm")
        : $class->ml("setting.randompaidgifts.option$iscomm");
    $ret .=
        "<p class='details'>" . $class->ml("setting.randompaidgifts.option.note$iscomm") . "</p>";
    $ret .= "</label>";

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $val = $class->get_arg( $args, "randompaidgifts" ) ? 'Y' : 'N';
    $u->set_prop( opt_randompaidgifts => $val );

    return 1;
}

1;
