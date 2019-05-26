#!/usr/bin/perl
#
# DW::Setting::ViewEntryStyle
#
# LJ::Setting module for specifying what style entries are
# displayed in for a user, such as mine, light, site, or original.
#
# Authors:
#      foxfirefey <foxfirefey@dreamwidth.org>
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010-2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::ViewEntryStyle;
use base 'DW::Setting::ViewStyle';
use strict;
use warnings;

sub label {
    return $_[0]->ml('setting.display.viewentrystyle.label');
}

sub option_ml {
    return $_[0]->ml('setting.display.viewentrystyle.option');
}

sub prop_name {
    return 'opt_viewentrystyle';
}

1;
