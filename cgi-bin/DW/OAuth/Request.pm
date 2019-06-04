#!/usr/bin/perl
#
# DW::OAuth
#
# OAuth Request Token
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::OAuth::Request;
use strict;
use warnings;

use Digest::SHA qw/sha1 sha256/;
use MIME::Base64::URLSafe;

use DW::OAuth;

# NOTE: This is not db-backed at all, and is memcache only.
# These are so short lived that there is no point to put them in the database.

sub from_token {
    my ( $class, $token ) = @_;
    return undef unless $token;
    return undef unless DW::OAuth->validate_token($token);

    {
        my $ar  = LJ::MemCache::get( [ $token, "oauth_request_token:" . $token ] );
        my $row = $ar ? LJ::MemCache::array_to_hash( "oauth_request", $ar ) : undef;
        return $class->new_from_row($row) if $row;
    }

    return undef;
}

sub want {
    my ( $class, $thing ) = @_;

    return undef unless $thing;
    return $thing if ref $thing eq $class;
    return $class->from_token($thing);
}

sub _make_simple {
    my $rv = 0;

    map { $rv += $_ } unpack( "LLLLL", $_[0] );

    return sprintf( "%08i", $rv % 100000000 );
}

sub new {
    my ( $class, $consumer, %opts ) = @_;

    my $c = DW::OAuth::Consumer->want($consumer);
    $opts{consumer_id} = $c->id if $c;

    # Required.
    die "Invalid consumer" unless $opts{consumer_id};

    $opts{callback} ||= 'oob';

    # Set some default options:
    if ( $opts{callback} eq 'oob' ) {
        $opts{simple_verifier} = 1 unless defined $opts{simple_verifier};
    }

    my ( $token, $secret ) = DW::OAuth->make_token_pair('request');

    $opts{token}  = $token;
    $opts{secret} = $secret;

    $opts{createtime} = time();

    my $verifier_string = sha1( $opts{token} . LJ::rand_chars(32) );
    if ( $opts{simple_verifier} ) {

        # this is a roundabout way to get a good 8-digit number
        # these don't have to be unique, just very hard to guess.
        $opts{verifier} = _make_simple($verifier_string);
    }
    else {
        $opts{verifier} = urlsafe_b64encode($verifier_string);
    }

    # change token into a simple token if that's requested
    if ( $opts{simple_token} ) {
        $opts{token} = _make_simple( $opts{token} );
    }

    delete $opts{user_id};

    my $rv = $class->new_from_row( \%opts );
    $rv->save;
    return $rv;
}

sub new_from_row {
    my ( $class, $row ) = @_;

    my $c = bless $row, $class;

    return $c;
}

sub save {
    my $c = $_[0];

    # This is intentionally only good for 600 seconds.
    my $expire = time() + 600;
    my $ar     = LJ::MemCache::hash_to_array( "oauth_request", $c );
    LJ::MemCache::set( [ $c->token, "oauth_request_token:" . $c->token ], $ar, $expire );
}

sub consumer_id {
    return $_[0]->{consumer_id};
}

sub consumer {
    return DW::OAuth::Consumer->from_id( $_[0]->consumer_id );
}

sub userid {
    if ( exists $_[1] ) {
        $_[0]->{userid} = $_[1];
    }
    else {
        return $_[0]->{userid};
    }
}

sub user {
    return $_[0]->userid ? LJ::load_userid( $_[0]->userid ) : undef;
}

sub token {
    return $_[0]->{token};
}

sub secret {
    return $_[0]->{secret};
}

sub createtime {
    return $_[0]->{createtime};
}

sub verifier {
    return $_[0]->{verifier};
}

sub callback {
    return $_[0]->{callback};
}

sub usable {
    my $r = $_[0];
    my $c = $r->consumer;

    return 0 unless $c;
    return 0 if exists $_[1] && $c->id != $_[1]->id;

    return 0 unless $c->usable;
    return 0 if $c->invalidatedtime && $r->createtime <= $c->invalidatedtime;
    return 1;
}

sub used {
    return $_[0]->{used} || 0;
}

sub delete {
    LJ::MemCache::delete( [ $_[0]->token, "oauth_request_token:" . $_[0]->token ] );
    $_[0]->{used} = 1;
}

1;
