#!/usr/bin/perl
#
# DW::Setting::DisplayEchi
#
# LJ::Setting module which controls whether to display the Explicit
# Comment Hierarchi Indicator (ECHI) for comments
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::DisplayEchi;
use base 'LJ::Setting::BoolSetting';
use strict;
use warnings;

sub prop_name {
    return "opt_echi_display";
}

sub checked_value {
    return "Y";
}

sub unchecked_value {
    return "";
}

sub should_render {
    my ( $class, $u ) = @_;
    return $u && $u->is_individual;
}

sub label {
    my $class = shift;
    return $class->ml('setting.echi_display.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    return $class->as_html( $u, $errs );
}

sub des {
    my $class = $_[0];

    return $class->ml('setting.echi_display.des');
}

1;
