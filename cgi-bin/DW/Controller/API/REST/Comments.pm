#!/usr/bin/perl
#
# DW::Controller::API::REST::Comments
#
# API controls for the comment system
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

package DW::Controller::API::Comments;
use DW::Controller::API::REST qw(path);

use strict;
use warnings;
use DW::Routing;
use DW::Request;
use DW::Controller;
use JSON;
use DW::Mood;

################################################
# /comments/settings
#
# Get a list of possible comment settings.
################################################
# Define route and associated params
my $settings = path('comments/settings.yaml', 1, {'get' => \&get_settings});


sub get_settings {
    my $self = $_[0];
    
    # we want to handle the not logged in case ourselves
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};

    my $settings = { "" => "Journal default comment settings",
					 "nocomments" => "Comments disabled.",
					 "noemail" => "Don't notify by email for comments."};

    return $self->rest_ok( $settings );
}

################################################
# /comments/screening
#
# Get a list of possible comment screening options.
################################################
# Define route and associated params
my $screening = path('comments/screening.yaml', 1, {'get' => \&get_screening});


sub get_screening {
    my $self = $_[0];
    
    # we want to handle the not logged in case ourselves
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};

    my $settings = {""   =>   "Journal Default",
                	"N"  =>   "No comments are screened.",
                	"R"  =>   "Screen anonymous comments",
                	"F"  =>   "Screen comments from journals without access granted.",
                	"A"  =>   "All comments are screened."};

    return $self->rest_ok( $settings );
}

1;
