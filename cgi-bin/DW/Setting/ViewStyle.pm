#!/usr/bin/perl
#
# DW::Setting::ViewStyle
#
# Generic LJ::Setting module for specifying what style journal views are
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

package DW::Setting::ViewStyle;
use base 'LJ::Setting';
use strict;
use warnings;

# Only override the below methods

sub label {
    die "Neglected to override 'label' in DW::Setting::ViewStyle subclass";
}

sub option_ml {
    die "Neglected to override 'option_ml' in DW::Setting::ViewStyle subclass";
}

sub prop_name {
    die "Neglected to override 'prop_name' in DW::Setting::ViewStyle subclass";
}

# Do not override any of these

sub should_render {
    my ( $class, $u ) = @_;

    return 0 unless $u;
    return $u->is_community ? 0 : 1;
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key  = $class->pkgkey;
    my $name = $class->prop_name;

    my $viewjournalstyle = $class->get_arg( $args, "viewjournalstyle" ) || $u->prop($name) || 'O';

    my @options = (
        O => $class->ml('setting.display.viewstyle.original'),
        M => $class->ml('setting.display.viewstyle.mine'),
        S => $class->ml('setting.display.viewstyle.site'),
        L => $class->ml('setting.display.viewstyle.light'),
    );

    my $ret = "<label for='${key}style'>" . $class->option_ml . "</label> ";
    $ret .= LJ::html_select(
        {
            name     => "${key}style",
            id       => "${key}style",
            selected => $viewjournalstyle,
        },
        @options
    );

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = uc( $class->get_arg( $args, "style" ) );

    $class->error( style => $class->ml('.setting.display.viewstyle.invalid') )
        unless $val =~ /^[OMSL]$/;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $name = $class->prop_name;

    my $val = $class->get_arg( $args, "style" );

    # don't save if this is the value we are already using
    return 1 if $u->prop($name) and $val eq $u->prop($name);

    # delete if we are turning it back to the default
    $val = "" if $val eq "O";

    $u->set_prop( $name, $val );
}

1;
