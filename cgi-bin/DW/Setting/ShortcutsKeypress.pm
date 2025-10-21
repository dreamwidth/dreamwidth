#!/usr/bin/perl
#
# DW::Setting::ShortcutsKeypress
#
# Base module for keyboard shortcus
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

package DW::Setting::ShortcutsKeypress;
use base 'LJ::Setting';
use strict;
use warnings;

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, $class->prop_key );

    unless ( length $val < 2 ) {
        $class->errors( $class->prop_key => "Single keys only" );
    }

    return 1;
}

sub should_render {
    my ( $class, $u ) = @_;
    return $u && $u->is_individual;
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $key = $class->pkgkey;

    my ( $keyval, $ctrlval, $altval, $metaval );
    if ($errs) {
        $keyval  = $class->get_arg( $args, $class->prop_key );
        $ctrlval = $class->get_arg( $args, $class->prop_key . 'ctrl' );
        $altval  = $class->get_arg( $args, $class->prop_key . 'alt' );
        $metaval = $class->get_arg( $args, $class->prop_key . 'meta' );
    }
    else {
        $keyval  = $u->prop( $class->prop_name );
        $ctrlval = $keyval =~ m/ctrl\+/;
        $altval  = $keyval =~ m/alt\+/;
        $metaval = $keyval =~ m/meta\+/;
        $keyval =~ s/.*\+//g;
    }
    my $ret;

    $ret .= LJ::html_text(
        {
            name      => "${key}" . $class->prop_key,
            id        => "${key}" . $class->prop_key,
            class     => "text",
            value     => $keyval,
            size      => 1,
            maxlength => 1 || undef
        }
    );

    $ret .= LJ::html_check(
        {
            name     => "${key}" . $class->prop_key . "ctrl",
            value    => 1,
            id       => "${key}ctrl",
            selected => $ctrlval,
        }
    );
    $ret .= " <label for='${key}ctrl'>";
    $ret .= "Ctrl";
    $ret .= "</label>";

    $ret .= LJ::html_check(
        {
            name     => "${key}" . $class->prop_key . "alt",
            value    => 1,
            id       => "${key}alt",
            selected => $altval,
        }
    );
    $ret .= " <label for='${key}alt'>";
    $ret .= "Alt";
    $ret .= "</label>";

    $ret .= LJ::html_check(
        {
            name     => "${key}" . $class->prop_key . "meta",
            value    => 1,
            id       => "${key}meta",
            selected => $metaval,
        }
    );
    $ret .= " <label for='${key}meta'>";
    $ret .= "Meta";
    $ret .= "</label>";

    my $errdiv = $class->errdiv( $errs, "code" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $val = $class->get_arg( $args, $class->prop_key );

    # prepend any modifiers
    if ( $class->get_arg( $args, $class->prop_key . 'ctrl' ) ) {
        $val = 'ctrl+' . $val;
    }
    if ( $class->get_arg( $args, $class->prop_key . 'alt' ) ) {
        $val = 'alt+' . $val;
    }
    if ( $class->get_arg( $args, $class->prop_key . 'meta' ) ) {
        $val = 'meta+' . $val;
    }

    $u->set_prop( $class->prop_name => $val );

    return 1;
}

1;
