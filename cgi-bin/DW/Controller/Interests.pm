#!/usr/bin/perl
#
# DW::Controller::Interests
#
# Outputs an account's interests in JSON format.
#
# Authors:
#      Thomas Thurman <thomas@thurman.org.uk>
#      foxfirefey <skittisheclipse@gmail.com>
#      Mark Smith <mark@dreamwidth.org>
#      Andrea Nall <anall@andreanall.com>
#      Sophie Hamilton <sophie-dw@theblob.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Interests;

use strict;
use warnings;
use DW::Routing;
use DW::Request;
use LJ::JSON;

DW::Routing->register_string(  "/data/interests", \&interests_handler, user => 1, format => 'json' );

my $formats = {
    'json' => sub { $_[0]->print( to_json( $_[1] ) ); },
};

sub interests_handler {
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

    # deal with renamed accounts
    my $renamed_u = $u->get_renamed_user;
    unless ( $renamed_u && $u->equals( $renamed_u ) ) {
        $r->header_out("Location", $renamed_u->journal_base . "/data/interests");
        $r->status( $r->REDIRECT );
        $r->print( to_json( { error => 'moved', moved_to => $renamed_u->journal_base . "/data/interests" } ) );
        return $r->OK;
    }

    # Load the interests
    my $interests = $u->get_interests() || [];
    my $output = {};
    foreach my $int ( @{ $interests } ) {
        $output->{ $int->[0] } = {
            interest => $int->[1],
            count    => $int->[2],
        };
    }
    # Contruct the JSON response hash
    my $response = {};

    $response->{account_id} = $u->userid;
    $response->{name} = $u->user;
    $response->{display_name} = $u->display_name if $u->is_identity;
    $response->{account_type} = $u->journaltype;
    $response->{interests} = $output;

    $format->( $r, $response );

    return $r->OK;
}

1;
