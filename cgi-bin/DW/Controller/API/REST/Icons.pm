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
my $route = __PACKAGE__->resource (
    path => '/users/{username}/icons/{picid}',
    ver => 1,
);

$route->path (
    $route->param({name => 'username', type => 'string', desc => 'The username you want icon information for', in => 'path', required => 1} ),
    $route->param({name => 'picid', type => 'integer', desc => 'The picid you want information for.', in => 'path'})
);

# define our parameters and options for GET requests
my $get = $route->get('Returns all icons for a specified username, or a single icon for a specified picid and username', \&rest_get);
$get->success('a list of icons');
$get->error(404, "No such userpic");

__PACKAGE__->register_rest_controller($route);

sub rest_get {

    my %responses = $route->{get}{responses};

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
            return $self->rest_error($responses{404});
        }
    } else {
        # otherwise, load all userpics.    
        my @icons = grep { ! ( $_->inactive || $_->expunged ) } LJ::Userpic->load_user_userpics( $u );
        return $self->rest_ok( \@icons );
    }

}


1;
