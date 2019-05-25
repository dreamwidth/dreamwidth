#!/usr/bin/perl
#
# DW::Setting::ShortcutsPrev
#
# LJ::Setting module which controls the keyboard shortcut for previous item
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

package DW::Setting::ShortcutsPrev;
use base 'DW::Setting::ShortcutsKeypress';
use strict;
use warnings;

sub prop_name {
    return "opt_shortcuts_prev";
}

sub label {
    my $class = shift;
    return $class->ml('setting.shortcuts.prev.label');
}

sub prop_key {
    return "shortcuts_prev";
}

1;
