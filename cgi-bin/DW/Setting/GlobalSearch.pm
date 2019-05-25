#!/usr/bin/perl
#
# DW::Setting::GlobalSearch
#
# Module to set the opt_blockglobalsearch setting.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::GlobalSearch;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    return $_[1] && ( $_[1]->is_person || $_[1]->is_community );
}

sub label {
    return $_[0]->ml('setting.globalsearch.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    # the selection values are opposite the text, since the property is an
    # opt-out property, it basically negates what we're trying to display to
    # the user ... yes, it's confusing, sorry
    my $sel = $class->get_arg( $args, "globalsearch" );
    $sel = $u->include_in_global_search ? 'N' : 'Y'
        unless defined $sel && length $sel;

    my $iscomm = $u->is_community ? '.comm' : '';

    my $ret .= LJ::html_select(
        {
            id       => "${key}globalsearch",
            name     => "${key}globalsearch",
            selected => $sel,
        },

        'N' => $class->ml("setting.globalsearch.sel.yes$iscomm"),
        'Y' => $class->ml("setting.globalsearch.sel.no$iscomm"),
    );

    my $errdiv = $class->errdiv( $errs, 'globalsearch' );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    # must be defined and Y or N
    my $val = $class->get_arg( $args, 'globalsearch' ) || 0;
    return unless defined $val && $val =~ /^[YN]$/;

    $u->set_prop( opt_blockglobalsearch => $val );

    return 1;
}

1;
