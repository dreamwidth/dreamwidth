#!/usr/bin/perl
#
# DW::Setting::Captcha
#
# LJ::Setting module for choosing the captcha type to display on this journal
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::Captcha;
use base 'LJ::Setting';
use strict;

use DW::Captcha;

sub should_render {
    my ( $class, $u ) = @_;
    return $u->is_identity ? 0 : 1;
}

sub label {
    my $class = shift;
    return $class->ml('setting.captcha.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $captcha_type = $class->get_arg( $args, "captcha" ) || $u->captcha_type;

    my @opts = (
        "T" => $class->ml("setting.captcha.option.select.text"),
        "I" => $class->ml("setting.captcha.option.select.image"),
    );

    my $ret;
    $ret .= "<label for='${key}captcha'>";
    $ret .= $class->ml('setting.captcha.option');
    $ret .= "</label> ";

    $ret .= LJ::html_select(
        {
            name     => "${key}captcha",
            id       => "${key}captcha",
            selected => $captcha_type
        },
        @opts
    );

    my $errdiv = $class->errdiv( $errs, "captcha" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $val = $class->get_arg( $args, "captcha" );
    $val = undef unless $val =~ /^[IT]$/;

    $u->captcha_type($val);

    return 1;
}

1;
