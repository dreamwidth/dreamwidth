#!/usr/bin/perl
#
# DW::Setting::ViewEntryStyle
#
# LJ::Setting module for specifying what style entries are
# displayed in for a user, such as mine, light, site, or original.
#
# Authors:
#      foxfirefey <foxfirefey@dreamwidth.org>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::ViewEntryStyle;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return 0 unless $u;
    return $u->is_community ? 0 : 1;
}

sub label {
    my ( $class, $u ) = @_;

    return $class->ml( 'setting.display.viewentrystyle.label' );
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $viewentrystyle = $class->get_arg( $args, "viewentrystyle" ) || $u->opt_viewentrystyle;

    my @options = (
        O => $class->ml( 'setting.display.viewstyle.original' ),
        S => $class->ml( 'setting.display.viewstyle.site' ),
        M => $class->ml( 'setting.display.viewstyle.mine' ),
        L => $class->ml( 'setting.display.viewstyle.light' ),
    );

    my $ret = "<label for='${key}viewentrystyle'>" . $class->ml( 'setting.display.viewentrystyle.option' ) . "</label> ";
    $ret .= LJ::html_select({
        name => "${key}viewentrystyle",
        id => "${key}viewentrystyle",
        selected => $viewentrystyle,
    }, @options );

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "viewentrystyle" );
    $class->errors( viewentrystyle => $class->ml( '.setting.display.viewstyle.invalid' ) ) unless $val =~ /^[OSML]$/;
    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $val = $class->get_arg( $args, "viewentrystyle" );

    # don't save if this is the value we are already using
    return 1 if $u->prop( 'opt_viewentrystyle' ) and $val eq $u->prop( 'opt_viewentrystyle' );

    # delete if we are turning it back to the default
    $val = "" if $val eq "O";

    $u->set_prop( "opt_viewentrystyle", $val );
}

1;
