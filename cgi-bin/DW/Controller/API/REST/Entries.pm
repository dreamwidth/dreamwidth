#!/usr/bin/perl
#
# DW::Controller::API::REST::Entries
#
# API controls for entries
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

package DW::Controller::API::REST::Entries;
use base 'DW::Controller::API::REST';

use strict;
use warnings;
use DW::Routing;
use DW::Request;
use DW::Controller;
use JSON;

# Define route and associated params
my $route_all = __PACKAGE__->resource (
    path => '/journals/{journal}/entries',
    ver => 1,
);

$route_all->path (
	$route_all->param({name => 'journal', type => 'string', desc => 'The journal you want entry information for', in => 'path', required => 1} )
);

# define our parameters and options for GET requests
my $get = $route_all->get('Returns recent entries for a specified journal', \&rest_get);
$get->success('a list of recent entries');

__PACKAGE__->register_rest_controller($route_all);

# Define route and associated params
my $route = __PACKAGE__->resource (
    path => '/journals/{journal}/entries/{entry_id}',
    ver => 1,
);

$route->path (
	$route->param({name => 'journal', type => 'string', desc => 'The journal you want entry information for', in => 'path', required => 1} ),
	$route->param({name => 'entry_id', type => 'integer', desc => 'The id of the entry you want information for.', in => 'path', required => 1})
);

# define our parameters and options for GET requests
my $get = $route->get('Returns a single entry for a specified entry id and journal', \&rest_get);
$get->success('An entry.');
$get->error(404, "No such item in that journal");

__PACKAGE__->register_rest_controller($route);

sub rest_get {
    my ( $self, $opts, $journalname, $ditemid ) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    my %responses = $route->{method}{GET}{responses};

    my $journal = LJ::load_user( $journalname );
    return $self->rest_error( "No such user: $journalname" ) unless $journal;

    if ($ditemid != "") {
	    my $item = LJ::Entry->new($journal, ditemid => $ditemid);
    	return $self->rest_error($responses{404}) unless $item;
    
    	return $self->rest_ok( $item );

	} else {
    
	    my $skip = 0;
	   
	    my $itemshow = 25;
	    my $viewall = 1;
	    my @itemids;
	    my $err;
	    my @items = $journal->recent_items(
	        clusterid     => $journal->{clusterid},
	        clustersource => 'slave',
	        viewall       => $viewall,
	        remote        => $rv->{remote},
	        itemshow      => $itemshow + 1,
	        skip          => $skip,
	        tagids        => [],
	        tagmode       => $opts->{tagmode},
	        security      => $opts->{securityfilter},
	        itemids       => \@itemids,
	        dateformat    => 'S2',
	        order         => $journal->is_community ? 'logtime' : '',
	        err           => \$err,
	        posterid      => undef,
	        );
	    foreach my $it ( @items ) {
	        my $itemid  = $it->{'itemid'};
	        my $ditemid = $itemid*256 + $it->{'anum'};
	        $it->{ditemid} = $ditemid;
	    }
	    return $self->rest_ok( \@items );
	}
}


1;
