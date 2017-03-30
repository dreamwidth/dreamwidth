#!/usr/bin/perl
#
# DW::Setting::RPAccount
#
# LJ::Setting module to let people ID their accounts as a roleplaying
# account
#
# Authors:
#      Denise Paolucci <denise@dreamwidth.org>
#
# Copyright (c) 2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::RPAccount;
use base 'LJ::Setting::BoolSetting';
use strict;
use warnings;

sub prop_name {
    return "opt_rpacct";
}

sub checked_value {
    return "Y";
}

sub unchecked_value {
    return "";
}

sub should_render {
    my ( $class, $u ) = @_;
    return $u && ( $u->is_individual || $u->is_community );
}

sub label {
    my $class = shift;
    return $class->ml( 'setting.rpaccount.label' );
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    return $class->as_html( $u, $errs );
}

sub des {
    my $class = $_[0];

    return $class->ml( 'setting.rpaccount.des' );
}

1;
