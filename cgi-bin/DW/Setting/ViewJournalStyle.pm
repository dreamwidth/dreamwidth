#!/usr/bin/perl
#
# DW::Setting::ViewJournalStyle
#
# LJ::Setting module for specifying what style entries are
# displayed in for a user.
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

package DW::Setting::ViewJournalStyle;
use base 'DW::Setting::ViewStyle';
use strict;
use warnings;

sub label {
    return $_[0]->ml('setting.display.viewjournalstyle.label');
}

sub option_ml {
    return $_[0]->ml('setting.display.viewjournalstyle.option');
}

sub prop_name {
    return 'opt_viewjournalstyle';
}

1;
