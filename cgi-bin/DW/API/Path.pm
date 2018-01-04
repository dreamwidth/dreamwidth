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
use YAML::XS qw'LoadFile';

use DW::API::Parameter;
use DW::API::Method;

use Carp qw(croak);

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(path);

# Usage: path ( yaml_source_path, ver, hash_of_HTTP_handlers ) 
# Creates a new path object for use in DW::Controller::API::REST 
#resource definitions from a OpenAPI-compliant YAML file and handler sub references

our %METHODS = (get => 1, post => 1, delete => 1);
our $API_PATH = "$ENV{LJHOME}/api/";

sub path {
    my ($source, $ver, $handlers) = @_;

    my $config = LoadFile($API_PATH . $source);

    my $route = {
    	ver => $ver};

    my $path;
    for my $key (keys $config->{paths}) {
    	$route->{'path'}{'name'} = $key;
    	$path = $key;
    }

    bless $route;

    if (exists $config->{paths}->{$path}->{parameters}) {
		for my $param (@{$config->{paths}->{$path}->{parameters}}) {
			my $new_param = DW::API::Parameter::define_parameter($param);
			$route->{path}{params}{$param->{name}} = $new_param;
			}
    	delete $config->{paths}->{$path}->{parameters};
    }

    for my $method (keys $config->{paths}->{$path}) {
		# make sure that it's a valid HTTP method, and we have a handler for it
		die "$method isn't a valid HTTP method" unless $METHODS{$method};
		die "No handler sub was passed for $method" unless $handlers->{$method};

		my $method_config = $config->{paths}->{$path}->{$method};
		$route->_add_method($method, $handlers->{$method}, $method_config);

    }
	DW::Controller::API::REST::register_rest_controller($route);
    return $route;
}

sub _add_method {
	my ($self, $method, $handler, $config) = @_;
		my $new_method = DW::API::Method::define_method($method, $handler, $config->{summary}, $config->{description});

		# add method params
		if (exists $config->{parameters}){
			for my $param (@{$config->{parameters}}) {
				$new_method->param($param);
			}
		}

		# add response descriptions
		for my $response (keys %{$config->{responses}}) {
			my $desc = $config->{$response}->{description};
			$new_method->response($response, $desc);
		}


	$self->{methods}->{$method} = $new_method;


}


1;
