#!/usr/bin/perl
#
# DW::Setting::ShortcutsPrev
#
# LJ::Setting module which controls the touch shortcut for previous item
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

package DW::Setting::ShortcutsTouchPrev;
use base 'DW::Setting::ShortcutsTouchGesture';
use strict;
use warnings;

sub prop_name {
    my $class = shift;
    return "opt_shortcuts_touch_prev";
}

sub label {
    my $class = shift;
    return $class->ml( 'setting.shortcuts_touch.prev.label' );
}

sub prop_key {
    my $class = shift;
    return "shortcuts_touch_prev";
}

1;
