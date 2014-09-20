#!/usr/bin/perl
#
# DW::Setting::JournalIconsStyle
#
# LJ::Setting module for specifying which view is displayed by default when
# viewing the user's own journal - the selected S2 style or the site style.
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

package DW::Setting::JournalIconsStyle;
use base 'DW::Setting::JournalStyle';
use strict;

sub label {
    return $_[0]->ml( 'setting.display.journaliconstyle.label2' );
}

sub option_ml {
    my ( $class, $u ) = @_;
    return $_[0]->ml('setting.display.journaliconstyle.option.comm')
        if $u && $u->is_community;
    return $_[0]->ml('setting.display.journaliconstyle.option');
}

sub note_ml {
    my ( $class, $u ) = @_;
    return $_[0]->ml('setting.display.journaliconstyle.note.comm')
        if $u && $u->is_community;
    return $_[0]->ml('setting.display.journaliconstyle.note');
}

sub prop_name {
    return 'use_journalstyle_icons_page';
}

sub store_negative {
    return 0;
}

1;
