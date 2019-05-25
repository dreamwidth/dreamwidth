#!/usr/bin/perl
#
# DW::Setting::ShortcutsTouch
#
# LJ::Setting module which controls whether or not to enable touch
# Shortcuts
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::ShortcutsTouch;
use base 'LJ::Setting::BoolSetting';
use strict;
use warnings;

sub prop_name {
    return "opt_shortcuts_touch";
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
    return $class->ml('setting.shortcuts_touch.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    return $class->as_html( $u, $errs );
}

sub des {
    my $class = $_[0];

    return $class->ml('setting.shortcuts_touch.des');
}

1;
