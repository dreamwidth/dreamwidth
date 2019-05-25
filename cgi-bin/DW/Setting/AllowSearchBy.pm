#!/usr/bin/perl
#
# DW::Setting::AllowSearchBy
#
# Module to set the opt_allowsearchby setting.
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

package DW::Setting::AllowSearchBy;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    return $_[1] && $_[1]->is_person;
}

sub label {
    return $_[0]->ml('setting.allowsearchby.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    # the selection values are opposite the text, since the property is an
    # opt-out property, it basically negates what we're trying to display to
    # the user ... yes, it's confusing, sorry
    my $sel = $class->get_arg( $args, "allowsearchby" ) || $u->prop('opt_allowsearchby') || 'F';

    my $ret .= LJ::html_select(
        {
            id       => "${key}allowsearchby",
            name     => "${key}allowsearchby",
            selected => $sel,
        },

        'A' => $class->ml('setting.allowsearchby.sel.a'),
        'F' => $class->ml('setting.allowsearchby.sel.f'),
        'N' => $class->ml('setting.allowsearchby.sel.n'),
    );

    my $errdiv = $class->errdiv( $errs, 'allowsearchby' );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    # must be defined and Y or N
    my $val = $class->get_arg( $args, 'allowsearchby' ) || 0;
    return unless defined $val && $val =~ /^[AFN]$/;

    $u->set_prop( opt_allowsearchby => $val );

    return 1;
}

1;
