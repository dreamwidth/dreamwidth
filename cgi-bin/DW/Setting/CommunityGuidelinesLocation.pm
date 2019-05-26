#!/usr/bin/perl
#
# DW::Setting::CommunityGuidelinesLocation
#
# DW::Setting module that lets you choose the location of the posting guidelines for a community
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::CommunityGuidelinesLocation;
use base 'LJ::Setting';
use strict;

sub should_render {
    my ( $class, $u ) = @_;

    return $u->is_community;
}

sub label {
    return $_[0]->ml('setting.communityguidelinesloc.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $communityguidelinesloc =
           $class->get_arg( $args, "communityguidelinesloc" )
        || $u->posting_guidelines_location
        || $LJ::DEFAULT_POSTING_GUIDELINES_LOC;

    my @options = (
        "N" => $class->ml('setting.communityguidelinesloc.option.select.none'),
        "P" => $class->ml('setting.communityguidelinesloc.option.select.profile'),
        "E" => $class->ml('setting.communityguidelinesloc.option.select.entry'),
    );

    my $select = LJ::html_select(
        {
            name     => "${key}communityguidelinesloc",
            id       => "${key}communityguidelinesloc",
            selected => $communityguidelinesloc,
        },
        @options
    );

    my $ret;
    $ret .= " <label for='${key}communityguidelinesloc'>";
    $ret .= $class->ml( "setting.communityguidelinesloc.option", { option => $select } );
    $ret .= "</label> ";

    my $errdiv = $class->errdiv( $errs, "communityguidelinesloc" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "communityguidelinesloc" );

    $class->errors(
        communityguidelinesloc => $class->ml('setting.communityguidelinesloc.error.invalid') )
        unless $val =~ /^(?:N|P|E)$/;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $val = $class->get_arg( $args, "communityguidelinesloc" );
    $u->posting_guidelines_location($val);

    return 1;
}

1;
