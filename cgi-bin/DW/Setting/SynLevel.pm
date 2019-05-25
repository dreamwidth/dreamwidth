#!/usr/bin/perl
#
# DW::Setting::SynLevel
#
# LJ::Setting module for selecting the syndication level for a journal's
# RSS or Atom feed.
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

package DW::Setting::SynLevel;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;
    return $u->is_identity ? 0 : 1;
}

sub label {
    return $_[0]->ml('setting.synlevel.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $synlevel = $class->get_arg( $args, "synlevel" ) || $u->prop("opt_synlevel");

    my @options = (
        "cut"     => $class->ml('setting.synlevel.option.select.cut'),
        "full"    => $class->ml('setting.synlevel.option.select.full'),
        "summary" => $class->ml('setting.synlevel.option.select.summary'),
        "title"   => $class->ml('setting.synlevel.option.select.title'),
    );

    my $ret;

    $ret .= " <label for='${key}synlevel'>";
    $ret .=
          $u->is_community
        ? $class->ml('setting.synlevel.option.comm')
        : $class->ml('setting.synlevel.option');
    $ret .= "</label>";

    $ret .= LJ::html_select(
        {
            name     => "${key}synlevel",
            id       => "${key}synlevel",
            selected => $synlevel,
        },
        @options
    );

    my $userdomain = $u->journal_base;

    $ret .= "<br />"
        . $class->ml(
        'setting.synlevel.option.note',
        {
            aopts_atom => "href='$userdomain/data/atom'",
            aopts_rss  => "href='$userdomain/data/rss'",
        }
        );

    my $errdiv = $class->errdiv( $errs, "synlevel" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "synlevel" );

    $class->errors( synlevel => $class->ml('setting.synlevel.error.invalid') )
        unless !$val || $val =~ /^(cut|full|summary|title)$/;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $val = $class->get_arg( $args, "synlevel" );
    $u->set_prop( "opt_synlevel" => $val );

    return 1;
}

1;
