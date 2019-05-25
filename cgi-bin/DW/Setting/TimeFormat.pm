#!/usr/bin/perl
##
## DW::Setting::TimeFormat
##
## DW::Setting module for choosing whether time stamps on entry pages and journals should appear
## in 24-hour or 12-hour time format
##
## Authors:
##      Rebecca Freiburg <beckyvi@gmail.com>
##
## Copyright (c) 2010 by Dreamwidth Studios, LLC.
##
## This program is free software; you may redistribute it and/or modify it under
## the same terms as Perl itself.  For a copy of the license, please reference
## 'perldoc perlartistic' or 'perldoc perlgpl'.
##

package DW::Setting::TimeFormat;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;
    return $u && $u->is_individual;
}

sub label {
    return $_[0]->ml('setting.timeformat.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $key = $class->pkgkey;
    my $ret;
    my $timeformat_24 =
        $errs ? $class->get_arg( $args, "timeformat_24" ) : $u->prop("timeformat_24");

    $ret .= LJ::html_check(
        {
            type     => "radio",
            name     => "${key}timeformat",
            id       => "${key}timeformat_12",
            value    => 0,
            selected => !$timeformat_24,
        }
    );
    $ret .=
          "<label for='${key}timeformat_12' class='radiotext'>"
        . $class->ml('setting.timeformat.option.12hour')
        . "</label>";
    $ret .= LJ::html_check(
        {
            type     => "radio",
            name     => "${key}timeformat",
            id       => "${key}timeformat_24",
            value    => 1,
            selected => $timeformat_24,
        }
    );
    $ret .=
          "<label for='${key}timeformat_24' class='radiotext'>"
        . $class->ml('setting.timeformat.option.24hour')
        . "</label>";

    return $ret;

}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "timeformat" );

    $class->errors( timeformat => $class->ml('setting.timeformat.error.invalid') )
        unless $val =~ /^[01]$/;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $val = $class->get_arg( $args, "timeformat" ) || 0;
    $u->set_prop( "timeformat_24" => $val );

    return 1;
}

1;
