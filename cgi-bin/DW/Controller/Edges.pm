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
#      Sophie Hamilton <sophie-dw@theblob.org>
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
    return $error_out->( $r->NOT_FOUND, 'Need account name as user parameter' ) unless $opts->username;
    my $u = LJ::load_user_or_identity( $opts->username )
        or return $error_out->( $r->NOT_FOUND, "invalid account" );

    # Check for other conditions
    return $error_out->( $r->HTTP_GONE, 'expunged' ) if $u->is_expunged;
    return $error_out->( $r->FORBIDDEN, 'suspended' ) if $u->is_suspended;
    return $error_out->( $r->NOT_FOUND, 'deleted' ) if $u->is_deleted;

    # Check whether the edge list is forced empty
    return $error_out->( $r->NOT_FOUND, 'edge lists disabled for this account' ) if exists $LJ::FORCE_EMPTY_SUBSCRIPTIONS{$u->id};

    # deal with renamed accounts
    my $renamed_u = $u->get_renamed_user;
    unless ( $renamed_u && $u->equals( $renamed_u ) ) {
        $r->header_out("Location", $renamed_u->journal_base . "/data/edges");
        $r->status( $r->REDIRECT );
        $r->print( to_json( { error => 'moved', moved_to => $renamed_u->journal_base . "/data/edges" } ) );
        return $r->OK;
    }

    # Load appropriate usernames for different accounts
    my $us;
    my %args = (
      limit => 5000,   # limit for each edge
    );

    my (@trusted, @watched, @trusted_by, @watched_by, @member_of, @maintainers, @moderators, @members) = ();

    if ( $u->is_individual ) {
        $us = LJ::load_userids(
            @trusted    = $u->trusted_userids( %args ),
            @watched    = $u->watched_userids( %args ),
            @trusted_by = $u->trusted_by_userids( %args ),
            @watched_by = $u->watched_by_userids( %args ),
            @member_of  = $u->member_of_userids( %args ),
        );
    } elsif ( $u->is_community ) {
        $us = LJ::load_userids(
            @maintainers = $u->maintainer_userids,
            @moderators  = $u->moderator_userids,
            @members     = $u->member_userids( %args ),
            @watched_by  = $u->watched_by_userids( %args ),
        );
    } elsif ( $u->is_syndicated ) {
        $us = LJ::load_userids(
            @watched_by  = $u->watched_by_userids( %args ),
        );
    }

    # Contruct the JSON response hash
    my $response = {};

    # all accounts have this
    $response->{account_id} = $u->userid;
    $response->{name} = $u->user;
    $response->{display_name} = $u->display_name if $u->is_identity;
    $response->{account_type} = $u->journaltype;
    $response->{watched_by} = \@watched_by;

    # different individual and community edges
   if ( $u->is_individual ) {
        $response->{trusted}    = \@trusted;
        $response->{watched}    = \@watched;
        $response->{trusted_by} = \@trusted_by;
        $response->{member_of}  = \@member_of;
    } elsif ( $u->is_community ) {
        $response->{maintainer} = \@maintainers;
        $response->{moderator}  = \@moderators;
        $response->{member}     = \@members;
    }

    # now dump information about the users we loaded
    $response->{accounts} = {
        map { $_ => { name => $us->{$_}->user, type => $us->{$_}->journaltype } } keys %$us
    };

    $format->( $r, $response );

    return $r->OK;
}

1;
