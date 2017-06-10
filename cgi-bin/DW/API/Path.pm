#!/usr/bin/perl
#
# DW::API::Path
#
# Defines Path objects and provides helper functions
# for use in DW::Controller::API::REST resources.
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

package DW::API::Path;

use strict;
use warnings;
use JSON;
use YAML qw'LoadFile';

use DW::API::Parameter;
use DW::API::Method;

use Carp qw(croak);

# Usage: path ( yaml_source_path, hash_of_HTTP_handlers ) 
# Creates a new path object for use in DW::Controller::API::REST 
#resource definitions from a OpenAPI-compliant YAML file and handler sub references

%METHODS = (get => 1, post => 1, delete => 1);

sub path {
    my ($source, %handlers) = @_;

    my $config = LoadFile($source);


    my %route = (
    	get_handler => $handlers{get},
    	post_handler => $hanlders{})

    for my $path (keys %$config) {
    	$route{'path'} = $path;
    }

    bless \%route;

    for my $method (keys $config->{$path}) {
		# first, make sure that it's a valid HTTP method, and we have a handler for it
		unless METHODS{$method} die "$method isn't a valid HTTP method";
		unless $handlers{$method} die "No handler sub was passed for $method";

		my $method_config = $config->{$path}->{$method};
		FIXME: make sure 
		\%route->_add_method($method, $handlers{$method}, $method_config)

    }

    return \%route;
}

sub _add_method {
	my ($self, $method, $handler, $config) = @_;
    		# FIXME: make sure Method def matches this.
		my $new_method = DW::API::Method::define_method($method, $handler, $config->{summary}, $config->{description})

		# add method params
		for my $param ($config->{parameters}) {
			$new_method->param($param);
		}

		# add response descriptions
		for my $response (keys $config->{responses}) {
			$new_method->response($config->{responses}->{$response});
		}


	$self->{methods}->{$method} = $new_method;


}

1;
