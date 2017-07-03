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
use DW::Controller::API::REST qw(path);
use strict;
use warnings;
use DW::Routing;
use DW::Request;
use DW::Controller;
#use DW::API::Path qw(path);
use JSON;

my $icons_all = path('icons_all.yaml', 1, {'get' => \&rest_get});
my $icons = path('icons.yaml', 1, {'get' => \&rest_get});

sub rest_get {
    my ( $self, $opts, $username, $picid ) = @_;

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
            return $self->rest_error("404");
        }
    } else {
        # otherwise, load all userpics.    
        my @icons = grep { ! ( $_->inactive || $_->expunged ) } LJ::Userpic->load_user_userpics( $u );
        return $self->rest_ok( \@icons );
    }

}


1;
