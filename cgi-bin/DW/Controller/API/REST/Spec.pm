#!/usr/bin/perl
#
# DW::Controller::API::REST::Spec
#
# API endpoint to return the API definition.
#
# Authors:
#      Ruth Hatch <ruth.s.hatch@gmail.com>
#
# Copyright (c) 2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::API::REST::Spec;
use DW::Controller::API::REST;

use strict;
use warnings;
use JSON;

# Define route and associated params
my $spec = DW::Controller::API::REST->path( 'spec.yaml', 1, { 'get' => \&rest_get } );

sub rest_get {
    my $self = $_[0];
    my $spec = _spec_20();
    my $ver  = $self->{ver};
    my %api  = %DW::Controller::API::REST::API_DOCS;

    $spec->{paths} = $api{$ver};

    return $self->rest_ok($spec);

}

sub _spec_20 {
    my $self = $_[0];
    my $ver  = $spec->{ver};

    my $security_defs =
        { "api_key" =>
            { "type" => "http", "scheme" => "Bearer", "bearerFormat" => "Bearer <api_key>" } };

    my %spec = (
        openapi => '3.0.0',
        servers => (
            {
                url => "$LJ::WEB_DOMAIN/api/v$ver"
            },
        ),
        info => {
            title       => "$LJ::SITENAME API",
            description => "An OpenAPI-compatible API for $LJ::SITENAME",
            version     => $ver,

        },
        security   => keys(%$security_defs),
        components => {
            securitySchemes => $security_defs,
        }
    );

    return \%spec;
}

1;
