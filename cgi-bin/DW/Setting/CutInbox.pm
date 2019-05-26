#!/usr/bin/perl
#
# DW::Setting::CutInbox
#
# LJ::Setting module which controls whether to respect cuts in the inbox
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::CutInbox;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;
    return $u && $u->is_individual;
}

sub label {
    my $class = shift;
    return $class->ml('setting.cutinbox.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $inbox_cut = $class->get_arg( $args, "cutinbox" ) || $u->cut_inbox;

    my $ret = LJ::html_check(
        {
            name     => "${key}cutinbox",
            id       => "${key}cutinbox",
            value    => 1,
            selected => $inbox_cut ? 1 : 0,
        }
    );
    $ret .= " <label for='${key}cutinbox'>" . $class->ml('setting.cutinbox.option') . "</label>";

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $val = $class->get_arg( $args, "cutinbox" ) ? "Y" : "N";
    $u->cut_inbox($val);

    return 1;
}

1;
