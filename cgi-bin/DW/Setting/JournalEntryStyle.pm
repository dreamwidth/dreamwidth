#!/usr/bin/perl
#
# DW::Setting::JournalEntryStyle
#
# LJ::Setting module for specifying which view is displayed by default when
# viewing the user's own journal - the selected S2 style or the site style.
#
# Authors:
#       Jen Griffin <kareila@livejournal.com>
#       Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2011-2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::JournalEntryStyle;
use base 'DW::Setting::JournalStyle';
use strict;

use LJ::S2;

sub label {
    return $_[0]->ml('setting.display.journalentrystyle.label2');
}

sub option_ml {
    my ( $class, $u ) = @_;
    return $_[0]->ml('setting.display.journalentrystyle.option.comm')
        if $u && $u->is_community;
    return $_[0]->ml('setting.display.journalentrystyle.option');
}

sub note_ml {
    my ( $class, $u ) = @_;
    return $_[0]->ml('setting.display.journalentrystyle.note.comm')
        if $u && $u->is_community;
    return $_[0]->ml('setting.display.journalentrystyle.note');
}

sub current_value {
    return LJ::S2::use_journalstyle_entry_page( $_[1] );
}

sub prop_name {
    return 'use_journalstyle_entry_page';
}

sub store_negative {
    return 1;
}

1;
