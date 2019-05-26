#!/usr/bin/perl
#
# DW::Setting::CutDisable
#
# LJ::Setting module for choosing whether or not to disable the
# display of entry cut text on a user's journal or reading page,
# as governed by the userprops "opt_cut_disable_journal" and
# "opt_cut_disable_reading"
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::CutDisable;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;
    return $u && !$u->is_syndicated;

    # identity users will only be shown opt_cut_disable_reading
}

sub label {
    my $class = shift;
    return $class->ml('setting.cutdisable.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $opt_reading = $u->prop("opt_cut_disable_reading") || 0;
    my $opt_journal = $u->prop("opt_cut_disable_journal") || 0;
    my $cutdisable = $class->get_arg( $args, "cutdisable" )
        || ( $opt_reading << 0 | $opt_journal << 1 );

    my @opts = (
        0 => $class->ml("setting.cutdisable.sel.none"),
        1 => $class->ml("setting.cutdisable.sel.reading"),
        2 => $class->ml("setting.cutdisable.sel.journal"),
        3 => $class->ml("setting.cutdisable.sel.both"),
    );
    @opts = @opts[ 0 .. 3 ] if $u->is_identity;

    my $ret;
    $ret .= "<label for='${key}cutdisable'>";
    $ret .= $class->ml('setting.cutdisable.option');
    $ret .= "</label> ";

    $ret .= LJ::html_select(
        {
            name     => "${key}cutdisable",
            id       => "${key}cutdisable",
            selected => $cutdisable
        },
        @opts
    );

    my $errdiv = $class->errdiv( $errs, "cutdisable" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $val = $class->get_arg( $args, "cutdisable" ) || 0;
    $u->set_prop( "opt_cut_disable_reading" => ( $val & 1 ) > 0 );
    $u->set_prop( "opt_cut_disable_journal" => ( $val & 2 ) > 0 )
        unless $u->is_identity;

    return 1;
}

1;
