#!/usr/bin/perl
#
# DW::Controller::API::REST::Moods
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

package DW::Controller::API::Moods;
use DW::Controller::API::REST qw(path);

use strict;
use warnings;
use DW::Routing;
use DW::Request;
use DW::Controller;
use JSON;
use DW::Mood;
#use DW::API::Path qw(path);

# Define route and associated params
my $moods = path('moods.yaml', 1, {'get' => \&rest_get_list});


sub rest_get_list {
    my $self = $_[0];
    
    # we want to handle the not logged in case ourselves
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};

    return $self->rest_ok( DW::Mood->get_moods );
}

1;
