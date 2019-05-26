#!/usr/bin/perl
#
# DW::Setting::ViewIconsStyle
#
# LJ::Setting module for specifying what style icon pages are
# displayed in for a user, such as mine, light, site, or original.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::ViewIconsStyle;
use base 'DW::Setting::ViewStyle';
use strict;
use warnings;

sub supports_site {
    return 1;
}

sub label {
    return $_[0]->ml('setting.display.viewiconstyle.label');
}

sub option_ml {
    return $_[0]->ml('setting.display.viewiconstyle.option');
}

sub prop_name {
    return 'opt_viewiconstyle';
}

1;
