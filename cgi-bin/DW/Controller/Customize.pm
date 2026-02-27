#!/usr/bin/perl
#
# DW::Controller::Customize
#
# This controller is for miscellanous style customization routes
#
# Authors:
#      Momiji <momijizukamori@gmail.com
#
# Copyright (c) 2010-2024 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Customize;

use strict;
use warnings;
use Carp qw/ croak confess /;

use DW::Controller;
use DW::Routing;
use DW::Template;
use LJ::JSON;

# routing directions
DW::Routing->register_string( '/customize/viewuser', \&viewuser_handler, app => 1 );

sub viewuser_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};
    my $get    = $r->{get_args};

    my $dbh    = LJ::get_db_writer();
    my $authas = $get->{authas} || $remote->{user};
    my $as     = $get->{as};
    my $u      = LJ::get_authas_user($authas);

    my $userid = $u->{'userid'};

    $u->preload_props( "stylesys", "s2_style" ) if $u;

    my ( $style, $layer );

    # when given 'w' argument, load user's current style, and edit the user layer.
    # this is the mode redirected to from /customize/ (the simple customization UI)
    if ( $u->{'stylesys'} == 2 ) {
        $style = LJ::S2::load_style( $u->{'s2_style'} );
        return error_ml("Style not found.")
            unless $style && $style->{userid} == $u->userid;
        $layer = LJ::S2::load_layer( $dbh, $style->{layer}->{user} );
    }

    return error_ml('/customize/viewuser.tt.no.user.layer2') unless $layer;
    return error_ml('/customize/viewuser.tt.layer.belongs')
        unless $layer->{userid} == $u->userid;
    return error_ml('/customize/viewuser.tt.layer.isnt.type2')
        unless $layer->{type} eq "user";

    my $lyr_layout = LJ::S2::load_layer( $dbh, $layer->{'b2lid'} );
    return error_ml( '/customize/viewuser.tt.layout.layer', { 'layertype' => $layer->{'type'} } )
        unless $lyr_layout;
    my $lyr_core = LJ::S2::load_layer( $dbh, $lyr_layout->{'b2lid'} );
    return error_ml('/customize/viewuser.tt.core.layer.for.layout')
        unless $lyr_core;

    $lyr_layout->{'uniq'} = $dbh->selectrow_array(
        "SELECT value FROM s2info WHERE s2lid=? AND infokey=?",
        undef, $lyr_layout->{'s2lid'},
        "redist_uniq"
    );

    my ( $lid_i18nc, $lid_theme, $lid_i18n );
    $lid_i18nc = $style->{'layer'}->{'i18nc'};
    $lid_theme = $style->{'layer'}->{'theme'};
    $lid_i18n  = $style->{'layer'}->{'i18n'};

    my $layerid = $layer->{'s2lid'};

    my @layers;
    push @layers,
        (
        [ 'core'   => $lyr_core->{'s2lid'} ],
        [ 'i18nc'  => $lid_i18nc ],
        [ 'layout' => $lyr_layout->{'s2lid'} ],
        [ 'i18n'   => $lid_i18n ]
        );

    if ( $layer->{'type'} eq "user" && $lid_theme ) {
        push @layers, [ 'theme' => $lid_theme ];
    }
    push @layers, [ $layer->{'type'} => $layer->{'s2lid'} ];

    my @layerids = grep { $_ } map { $_->[1] } @layers;
    LJ::S2::load_layers(@layerids);

    my %layerinfo;

    # load the language and layout choices for core.
    LJ::S2::load_layer_info( \%layerinfo, \@layerids );

    my @props;
    foreach my $prop ( S2::get_properties( $lyr_layout->{'s2lid'} ) ) {
        $prop = S2::get_property( $lyr_core->{'s2lid'}, $prop )
            unless ref $prop;
        next unless ref $prop;
        next if $prop->{'noui'};

        my $name = $prop->{'name'};
        my $type = $prop->{'type'};

        # figure out existing value (if there was no user/theme layer)
        my $existing;
        foreach my $lid ( reverse @layerids ) {
            next if $lid == $layerid;
            $existing = S2::get_set( $lid, $name );
            last if defined $existing;
        }

        if ( ref $existing eq "HASH" ) { $existing = $existing->{'as_string'}; }
        my $val          = S2::get_set( $layerid, $name );
        my $had_override = defined $val;
        $val = $existing unless $had_override;
        if ( ref $val eq "HASH" ) { $val = $val->{'as_string'}; }

        next if $as eq "" && !$had_override;
        next if $as eq "theme" && $type ne "Color";

        $val = LJ::S2::convert_prop_val( $prop, $val );
        push @props, ( { name => $name, val => $val } );
    }

    my $vars = {
        authas_form => $rv->{authas_form},
        u           => $rv->{u},
        as          => $as,
        props       => \@props,
        layer       => $lyr_layout
    };

    return DW::Template->render_template( 'customize/viewuser.tt', $vars );
}

1;
