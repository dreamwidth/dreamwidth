#!/usr/bin/perl
#
# DW::Controller::Support::Search
#
# The search controller for support.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Support::Search;

use strict;
use DW::Routing;
use DW::Request;
use DW::Controller;
use Storable;

DW::Routing->register_string( "/support/search", \&search_handler, app => 1 );

sub search_handler {
    my ( $ok, $rv ) = controller( authas => 1, form_auth => 0 );
    return $rv unless $ok;
    my $remote = $rv->{remote};

    my $r = DW::Request->get;
    return DW::Template->render_template( 'support/search.tt' )
        unless $r->did_post;

    # POST logic, for doing the actual search.
    my $args = $r->post_args;
    die "Invalid form auth.\n"
        unless LJ::check_form_auth( $args->{lj_form_auth} );

    $rv = do_search( remoteid => $remote->id,
                        query => $args->{query},
                       offset => $args->{offset} );

    return DW::Template->render_template( 'support/search.tt', $rv );
}

# helper subroutine that can be called from other contexts

sub do_search {
    my %args = @_;

    my $remoteid = delete $args{remoteid} or die "No remoteid";
    my $q = LJ::strip_html( LJ::trim( delete $args{query} ) );
    my $offset = ( delete $args{offset} // 0 ) + 0;
    die "Unknown opts to do_search" if %args;

    my $gc = LJ::gearman_client();
    die "Sorry, content searching is not configured on this server.\n"
        unless $gc && @LJ::SPHINX_SEARCHD;

    my $error = sub { return { query => $q, error => $_[0] } };
    my $ok    = sub { return { query => $q, offset => $offset,
                               result => $_[0] } };

    return $error->( "Please specify a shorter search string." )
        if length $q > 255;
    return $error->( "Please specify a search string." )
        unless length $q > 0;
    return $error->( "Offset must be between 0 and 1000." )
        unless $offset >= 0 && $offset <= 1000;

    # Gearman worker takes a blob, we send it a frozen hash.
    my $search_args = { remoteid => $remoteid, query => $q,
        offset => $offset, support => 1 };
    my $arg = Storable::nfreeze( $search_args );

    # Build the actual task we're sending to Gearman for searching.
    my $result;
    my $task = Gearman::Task->new(
        'sphinx_search', \$arg,
        {
            uniq => '-',
            on_complete => sub {
                my $res = $_[0] or return undef;
                $result = Storable::thaw( $$res );
            },
        }
    );

    # Fire the job and wait a bit. Times out if we don't get a response.
    my $ts = $gc->new_task_set();
    $ts->add_task( $task );
    $ts->wait( timeout => 20 );

    return $error->( "Sorry, the request timed out or search is down." )
        unless ref $result eq 'HASH';
    return $error->( "Sorry, there were no results found for that search." )
        if $result->{total} <= 0;

    return $ok->( $result );
}

1;
