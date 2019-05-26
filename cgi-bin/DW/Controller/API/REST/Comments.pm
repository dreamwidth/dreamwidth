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
use DW::Controller::API::REST;

use strict;
use warnings;
use JSON;

################################################
# /comments/screening
#
# Get a list of possible comment screening options.
################################################
# Define route and associated params
my $screening =
    DW::Controller::API::REST->path( 'comments/screening.yaml', 1, { 'get' => \&get_screening } );

sub get_screening {
    my $self = $_[0];

    my $settings = {
        ""  => "Journal Default",
        "N" => "No comments are screened.",
        "R" => "Screen anonymous comments",
        "F" => "Screen comments from journals without access granted.",
        "A" => "All comments are screened."
    };

    return $self->rest_ok($settings);
}

1;
