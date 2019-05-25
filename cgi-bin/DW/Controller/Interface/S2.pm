#!/usr/bin/perl
#
# DW::Controller::Interface::S2
#
# This controller is for the s2 interface
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Interface::S2;

use strict;
use warnings;
use DW::Routing;
use DW::Auth;

# handle, even with no id, so that we can present an informative error message
DW::Routing->register_regex(
    '^/interface/s2(?:/(\d+)?)?$', \&interface_handler,
    app     => 1,
    format  => 'plain',
    methods => { GET => 1, PUT => 1 }
);

# handles menu nav pages
sub interface_handler {
    my ( $call_info, $layerid ) = @_;
    my $r      = DW::Request->get;
    my $method = $r->method;

    $layerid = int( $layerid || 0 ) || '';
    return error( $r, $r->NOT_FOUND, 'No layerid',
        'Must provide the layerid, e.g., /interface/s2/1234' )
        unless $layerid;

    my $lay = LJ::S2::load_layer($layerid);
    return error(
        $r, $r->NOT_FOUND,
        'Layer not found',
        "There is no layer with id '$layerid' at this site"
    ) unless $lay;

    my ($remote) = DW::Auth->authenticate( remote => 1, digest => 1 );
    return error( $r, $r->HTTP_UNAUTHORIZED, 'Unauthorized',
        "You must send your $LJ::SITENAME username and password or a valid session cookie\n" )
        unless $remote;

    my $layeru = LJ::load_userid( $lay->{userid} );
    return error( $r, $r->SERVER_ERROR, "Error", "Unable to find layer owner" )
        unless $layeru;

    if ( $method eq 'GET' ) {
        return error( $r, $r->FORBIDDEN, 'Forbidden',
            "You are not authorized to retrieve this layer" )
            unless $layeru->user eq "system" || $remote->can_manage($layeru);

        my $layerinfo = {};
        LJ::S2::load_layer_info( $layerinfo, [$layerid] );
        my $srcview =
            exists $layerinfo->{$layerid}->{source_viewable}
            ? $layerinfo->{$layerid}->{source_viewable}
            : 1;

        # Disallow retrieval of protected system layers
        return error( $r, $r->FORBIDDEN, 'Forbidden', "The requested layer is restricted" )
            if $layeru->user eq "system" && !$srcview;

        my $s2code = LJ::S2::load_layer_source($layerid);
        $r->content_type("application/x-danga-s2-layer");
        $r->print($s2code);

        return $r->OK;
    }
    elsif ( $method eq 'PUT' ) {
        return error( $r, $r->FORBIDDEN, 'Forbidden', 'You are not authorized to edit this layer' )
            unless $remote->can_manage($layeru);

        return error( $r, $r->FORBIDDEN, 'Forbidden',
            'Your account type is not allowed to edit layers' )
            unless $remote->can_create_s2_styles;

        # Read in the entity body to get the source
        my $len = $r->header_in("Content-length") + 0;

        return error( $r, $r->HTTP_BAD_REQUEST, 'Bad Request',
            'Supply S2 layer code in the request entity body and set Content-length' )
            unless $len;

        return error(
            $r,
            $r->HTTP_UNSUPPORTED_MEDIA_TYPE,
            'Unsupported Media Type',
            'Request body must be of type application/x-danga-s2-layer'
        ) unless lc( $r->header_in('Content-type') ) eq 'application/x-danga-s2-layer';

        my $s2code;
        $r->read( $s2code, $len );

        my $error = "";
        LJ::S2::layer_compile( $lay, \$error, { s2ref => \$s2code } );

        if ($error) {
            error(
                $r, $r->HTTP_SERVER_ERROR,
                "Layer Compile Error",
                "An error was encountered while compiling the layer."
            );

            ## Strip any absolute paths
            $error =~ s/LJ::.+//s;
            $error =~ s!, .+?(src/s2|cgi-bin)/!, !g;

            $r->print($error);
            return $r->OK;
        }
        else {
            $r->status_line("201 Compiled and Saved");
            $r->header_out( Location => "$LJ::SITEROOT/interface/s2/$layerid" );
            $r->print("Compiled and Saved\nThe layer was uploaded successfully.\n");

            return $r->OK;
        }
    }
}

sub error {
    my ( $r, $code, $string, $long ) = @_;

    $r->status_line("$code $string");
    $r->print("$string\n$long\n");

    # Tell Apache OK so it won't try to handle the error
    return $r->OK;
}

1;
