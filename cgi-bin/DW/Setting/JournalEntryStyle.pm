#!/usr/bin/perl
#
# DW::Setting::JournalEntryStyle
#
# LJ::Setting module for specifying which view is displayed by default when
# viewing the user's own journal - the selected S2 style or the site style.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::JournalEntryStyle;
use base 'LJ::Setting';
use strict;

use LJ::S2;

sub should_render {
    my ( $class, $u ) = @_;

    return 0 unless $u;
    return $u->is_syndicated ? 0 : 1;
}

sub label {
    my ( $class, $u ) = @_;

    return $class->ml( 'setting.display.journalentrystyle.label' );
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $use_s2 = $class->get_arg( $args, "journalentrystyle" ) ||
        LJ::S2::use_journalstyle_entry_page( $u );

    my $ret = LJ::html_check( {
        name => "${key}journalentrystyle",
        id => "${key}journalentrystyle",
        value => 1,
        selected => $use_s2 ? 1 : 0,
    } );
    $ret .= " <label for='${key}journalentrystyle'>" . $class->ml('setting.display.journalentrystyle.option') . "</label>";
    $ret .= "<br /><i>" . $class->ml('setting.display.journalentrystyle.note') . "</i>";

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $val = $class->get_arg( $args, "journalentrystyle" ) ? "Y" : "N";
    $u->set_prop( use_journalstyle_entry_page => $val );

    return 1;
}

1;
