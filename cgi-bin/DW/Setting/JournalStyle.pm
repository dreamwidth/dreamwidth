#!/usr/bin/perl
#
# DW::Setting::JournalStyle
#
# LJ::Setting module for specifying which view is displayed by default when
# viewing the user's own journal - the selected S2 style or the site style.
#
# Authors:
#       Jen Griffin <kareila@livejournal.com>
#       Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2011-2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::JournalStyle;
use base 'LJ::Setting';
use strict;

# Only override the below methods

sub label {
    die "Neglected to override 'label' in DW::Setting::JournalStyle subclass";
}

sub option_ml {
    die "Neglected to override 'option_ml' in DW::Setting::JournalStyle subclass";
}

sub note_ml {
    return undef;
}

sub prop_name {
    die "Neglected to override 'prop_name' in DW::Setting::JournalStyle subclass";
}

sub current_value {
    return $_[1]->prop( $_[0]->prop_name );
}

sub store_negative {
    return 0;
}

# Do not override any of these

sub should_render {
    my ( $class, $u ) = @_;

    return 0 unless $u;
    return $u->is_syndicated ? 0 : 1;
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $use_s2 = $class->get_arg( $args, "style" )
        || $class->current_value($u);

    my $ret = LJ::html_check(
        {
            name     => "${key}style",
            id       => "${key}style",
            value    => 1,
            selected => $use_s2 ? 1 : 0,
        }
    );
    $ret .= " <label for='${key}style'>" . $class->option_ml($u) . "</label>";

    my $note = $class->note_ml($u);
    $ret .= "<br /><i>$note</i>" if $note;

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $name  = $class->prop_name;
    my $value = $class->get_arg( $args, "style" );
    my $out   = undef;

    if ( $class->store_negative ) {
        $out = $value ? 'Y' : 'N';
    }
    elsif ($value) {
        $out = 'Y';
    }

    $u->set_prop( $name => $out );

    return 1;
}

1;
