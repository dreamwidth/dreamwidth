#!/usr/bin/perl
#
# DW::Controller::Edges
#
# Outputs an account's edges in JSON format.
#
# Authors:
#      Thomas Thurman <thomas@thurman.org.uk>
#      foxfirefey <skittisheclipse@gmail.com>
#      Mark Smith <mark@dreamwidth.org>
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Edges;

use strict;
use warnings;
use DW::Routing;
use DW::Request;
use LJ::JSON;

DW::Routing->register_string(  "/data/edges", \&edges_handler, user => 1, format => 'json' );

my $formats = {
    'json' => sub { $_[0]->print( to_json( $_[1] ) ); },
};

sub edges_handler {
    my $opts = shift;
    my $r = DW::Request->get;

    my $format = $formats->{ $opts->format };

    # Outputs an error message
    my $error_out = sub {
       my ( $code, $message ) = @_;
       $r->status( $code );
       $format->( $r, { error => $message } );

       return $r->OK;
    };

    # Load the account or error
    return $error_out->(404, 'Need account name as user parameter') unless $opts->username;
    my $u = LJ::load_user_or_identity( $opts->username )
        or return $error_out->( 404, "invalid account");

    # Check for other conditions
    return $error_out->( 410, 'expunged' ) if $u->is_expunged;
    return $error_out->( 403, 'suspended' ) if $u->is_suspended;
    return $error_out->( 404, 'deleted' ) if $u->is_deleted;

    # Load appropriate usernames for different accounts
    my $us;

    if ( $u->is_individual ) {
        $us = LJ::load_userids( $u->trusted_userids, $u->watched_userids, $u->trusted_by_userids, $u->watched_by_userids, $u->member_of_userids );
    } elsif ( $u->is_community ) {
        $us = LJ::load_userids( $u->maintainer_userids, $u->moderator_userids, $u->member_userids, $u->watched_by_userids );
    } elsif ( $u->is_syndicated ) {
        $us = LJ::load_userids( $u->watched_by_userids );
    }

    # Contruct the JSON response hash
    my $response = {};

    # all accounts have this
    $response->{account_id} = $u->userid;
    $response->{name} = $u->user;
    $response->{display_name} = $u->display_name if $u->is_identity;
    $response->{account_type} = $u->journaltype;
    $response->{watched_by} = [ $u->watched_by_userids ];

    # different individual and community edges
    if ( $u->is_individual ) {
        $response->{trusted} = [ $u->trusted_userids ];
        $response->{watched} = [ $u->watched_userids ];
        $response->{trusted_by} = [ $u->trusted_by_userids ];
        $response->{member_of} = [ $u->member_of_userids ];
    } elsif ( $u->is_community ) {
        $response->{maintainer} = [ $u->maintainer_userids ];
        $response->{moderator} = [ $u->moderator_userids ];
        $response->{member} = [ $u->member_userids ];
    }

    # now dump information about the users we loaded
    $response->{accounts} = {
        map { $_ => { name => $us->{$_}->user, type => $us->{$_}->journaltype } } keys %$us
    };

    $format->( $r, $response );

    return $r->OK;
}

1;
