#!/usr/bin/perl
#
# DW::Controller::API::REST::Icons
#
# API controls for the icon system
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2016 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::API::Rest::Icons;
use base 'DW::Controller::API::REST';

use strict;
use warnings;
use DW::Routing;
use DW::Request;
use DW::Controller;
use JSON;

# Define route and associated params
my %route = (
    path => '/users/{username}/icons/{picid}',
    params => {
        username => {
            type => 'string',
            desc => 'The username you want icon information for',
            required => 1,
        },
        picid => {
            type => 'integer',
            desc => 'The picid you want information for.',
        }, 
    }, 
    ver => 1,
);

# 
sub rest_get {

    my %errors = (402 => {description => "No such userpic"} );

    $route{method}{get} = {
        description => 'Returns all icons for a specified username',
        success => {    description => 'a list of icons',
                        schema => '',
                    },
        errors => \%errors
    };

    warn("icon list handler!");
    my ( $self, $opts, $username, $picid ) = @_;
    warn("username=$username");
    my $u = LJ::load_user( $username );

    # we want to handle the not logged in case ourselves
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    # if we're given a picid, try to load that userpic
    if ($picid != "") {
        my $userpic = LJ::Userpic->new( $u, $picid );
        if ( $userpic ) {
            return $self->rest_ok( $userpic );
        } else {
            return $self->rest_error($errors{402});
        }
    } else {
        # otherwise, load all userpics.    
        my @icons = grep { ! ( $_->inactive || $_->expunged ) } LJ::Userpic->load_user_userpics( $u );
        return $self->rest_ok( \@icons );
    }

}

# # 
# sub rest_get_item {


#     $get{item} = {
#         description => 'Returns icon with a given picid for a specified username'
#         success => {    description => 'a list of icons'
#                         schema => ''
#                     }
#         errors => %errors
#     }

#     my ( $self, $opts, $username, $picid ) = @_;
#     warn("icon itom handler!");
#     warn("username=$username");
#     my $u = LJ::load_user( $username );

#     # we want to handle the not logged in case ourselves
#     my ( $ok, $rv ) = controller( anonymous => 1 );
#     return $rv unless $ok;

#     my $userpic = LJ::Userpic->new( $u, $picid );
#     if ( $userpic ) {
#         return $self->rest_ok( $userpic );
#     } else {
#         return $self->rest_error($error{402});
#     }
# }


# register the endpoints
__PACKAGE__->register_rest_controller( \%route);

1;
