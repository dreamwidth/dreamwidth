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

# register the endpoints
__PACKAGE__->register_rest_controller( '^/users/([^/]*)/icons', 1 );

# 
sub rest_get_list {
    warn("icon list handler!");
    my ( $self, $opts, $username ) = @_;
    warn("username=$username");
    my $u = LJ::load_user( $username );

    # we want to handle the not logged in case ourselves
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my @icons = grep { ! ( $_->inactive || $_->expunged ) } LJ::Userpic->load_user_userpics( $u );
    return $self->rest_ok( \@icons );
}

# 
sub rest_get_item {
    my ( $self, $opts, $username, $picid ) = @_;
    warn("icon itom handler!");
    warn("username=$username");
    my $u = LJ::load_user( $username );

    # we want to handle the not logged in case ourselves
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $userpic = LJ::Userpic->new( $u, $picid );
    if ( $userpic ) {
        return $self->rest_ok( $userpic );
    } else {
        return $self->rest_error( 402, "No such userpic for $username $picid" );
    }
}

1;
