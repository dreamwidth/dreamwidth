#!/usr/bin/perl
#
# DW::Setting::GoogleAnalytics4
#
# LJ::Setting module for Google Analytics version 4
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2009-2023 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Setting::GoogleAnalytics4;
use base 'LJ::Setting';
use strict;
use warnings;
use LJ::Global::Constants;

sub should_render {
    my ( $class, $u ) = @_;

    return $u && $u->can_use_google_analytics ? 1 : 0;
}

sub label {
    return $_[0]->ml('setting.googleanalytics4.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $key = $class->pkgkey;
    my $ret;

    $ret .= LJ::html_text(
        {
            name      => "${key}code",
            id        => "${key}code",
            class     => "text",
            value     => $errs ? $class->get_arg( $args, "code" ) : $u->ga4_analytics,
            size      => 30,
            maxlength => 100,
        }
    );

    my $errdiv = $class->errdiv( $errs, "code" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $txt = $class->get_arg( $args, "code" ) || '';
    $txt = LJ::text_trim( $txt, 0, 100 );

    # Check that the ID matches the format G-xxxxxxxxxx
    # or is blank before proceeding.
    if ( $txt =~ /^G-[A-Z0-9]{10,}$/i or $txt eq "" ) {
        $u->ga4_analytics(uc $txt);
    }
    else {
        $class->errors( "code" => $class->ml('setting.googleanalytics4.error.invalid') );
    }
    return 1;
}

1;
