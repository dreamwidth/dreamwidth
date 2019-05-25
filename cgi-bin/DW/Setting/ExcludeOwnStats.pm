#!/usr/bin/perl
#
# DW::Setting::ExcludeOwnStats
#
# LJ::Setting module for excluding self from your own statistics
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Setting::ExcludeOwnStats;
use base 'LJ::Setting';
use strict;
use warnings;
use LJ::Global::Constants;

sub should_render {
    my ( $class, $u ) = @_;

    return $u && $u->can_use_page_statistics && $u->is_individual ? 1 : 0;
}

sub label {
    return $_[0]->ml('setting.excludeownstats.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $key = $class->pkgkey;

    my $exclude = $class->get_arg( $args, "exclude" ) || $u->exclude_from_own_stats;

    my $ret = LJ::html_check(
        {
            name     => "${key}exclude",
            id       => "${key}exclude",
            value    => 1,
            selected => $exclude ? 1 : 0,
        }
    );
    $ret .=
        " <label for='${key}exclude'>" . $class->ml('setting.excludeownstats.option') . "</label>";

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $val = $class->get_arg( $args, "exclude" ) ? "1" : "0";
    $u->exclude_from_own_stats($val);

    return 1;
}

1;
