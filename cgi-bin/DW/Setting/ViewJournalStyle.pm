#!/usr/bin/perl
#
# DW::Setting::ViewJournalStyle
#
# LJ::Setting module for specifying what style entries are
# displayed in for a user.
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

package DW::Setting::ViewJournalStyle;
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

    return $class->ml( 'setting.display.viewjournalstyle.label' );
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $viewjournalstyle = $class->get_arg( $args, "viewjournalstyle" ) || $u->opt_viewjournalstyle;

    my @options = (
        O => $class->ml( 'setting.display.viewstyle.original' ),
        M => $class->ml( 'setting.display.viewstyle.mine' ),
        # Todo: make this a viable option!  Needs some styling.
        #S => $class->ml( 'setting.display.viewstyle.site' ),
        L => $class->ml( 'setting.display.viewstyle.light' ),
    );

    my $ret = "<label for='${key}viewjournalstyle'>" . $class->ml( 'setting.display.viewjournalstyle.option' ) . "</label> ";
    $ret .= LJ::html_select({
        name => "${key}viewjournalstyle",
        id => "${key}viewjournalstyle",
        selected => $viewjournalstyle,
    }, @options );

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "viewjournalstyle" );
    $class->errors( viewjournalstyle => $class->ml( '.setting.display.viewstyle.invalid' ) ) unless $val =~ /^[OSML]$/;
    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $val = $class->get_arg( $args, "viewjournalstyle" );

    # don't save if this is the value we are already using
    return 1 if $u->prop( 'opt_viewjournalstyle' ) and $val eq $u->prop( 'opt_viewjournalstyle' );

    # delete if we are turning it back to the default
    $val = "" if $val eq "O";

    $u->set_prop( "opt_viewjournalstyle", $val );
}

1;
