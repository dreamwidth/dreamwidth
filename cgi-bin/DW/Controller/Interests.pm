#!/usr/bin/perl
#
# DW::Controller::Interests
#
# Outputs an account's interests in JSON format.
#
# Authors:
#      Sophie Hamilton <sophie-dw@theblob.org>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Interests;

use strict;
use DW::Routing;
use DW::Request;
use LJ::JSON;

DW::Routing->register_string( "/data/interests", \&interests_handler, user => 1, format => 'json' );

my $formats = { 'json' => sub { $_[0]->print( to_json( $_[1] ) ); }, };

sub interests_handler {
    my $opts = shift;
    my $r    = DW::Request->get;

    my $format = $formats->{ $opts->format };

    # Outputs an error message
    my $error_out = sub {
        my ( $code, $message ) = @_;
        $r->status($code);
        $format->( $r, { error => $message } );

        return $r->OK;
    };

    # Load the account or error
    return $error_out->( $r->NOT_FOUND, 'Need account name as user parameter' )
        unless $opts->username;
    my $u = LJ::load_user_or_identity( $opts->username )
        or return $error_out->( $r->NOT_FOUND, "invalid account" );

    # Check for other conditions
    return $error_out->( $r->HTTP_GONE, 'expunged' )  if $u->is_expunged;
    return $error_out->( $r->FORBIDDEN, 'suspended' ) if $u->is_suspended;
    return $error_out->( $r->NOT_FOUND, 'deleted' )   if $u->is_deleted;

    # Load the interests
    my $interests = $u->get_interests || [];
    my $output    = {};
    foreach my $int ( @{$interests} ) {
        $output->{ $int->[0] } = {
            interest => $int->[1],
            count    => $int->[2],
        };
    }

    # Contruct the JSON response hash
    my $response = {};

    $response->{account_id}   = $u->userid;
    $response->{name}         = $u->user;
    $response->{display_name} = $u->display_name if $u->is_identity;
    $response->{account_type} = $u->journaltype;
    $response->{interests}    = $output;

    $format->( $r, $response );

    return $r->OK;
}

1;
