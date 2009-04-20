#!/usr/bin/perl
#
# DW::Shop::Engine::PayPal
#
# The interface to PayPal's flow.  Responsible for doing all of the per-engine
# custom flow.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Shop::Engine::PayPal;

use strict;
use Carp qw/ croak confess /;
use Storable qw/ nfreeze thaw /;

use base qw/ DW::Shop::Engine /;


# new( $cart )
#
# instantiates a new PayPal engine for the given cart
sub new {
    return bless { cart => $_[1] }, $_[0];
}


# new_from_token( $token )
#
# constructs an engine and cart from a given token.
sub new_from_token {
    my ( $class, $token ) = @_;

    my $dbh = DW::Pay::get_db_writer()
        or die "Database temporarily unavailable.\n"; # no object yet

    my ( $ppid, $itime, $ttime, $cartid, $status ) =
        $dbh->selectrow_array( 'SELECT ppid, inittime, touchtime, cartid, status FROM pp_tokens WHERE token = ?', undef, $token );
    return undef
        unless $cartid;

    my $cart = DW::Shop::Cart->get_from_cartid( $cartid );
    die "Invalid shopping cart.\n"
        unless $cart;

    return bless {
        ppid => $ppid,
        inittime => $itime,
        touchtime => $ttime,
        token => $token,
        status => $status,
        cart => $cart,
    }, $class;
}


# checkout_url()
#
# given a shopping cart full of Stuff, build a URL for us to send the user to
# to initiate the checkout process.
sub checkout_url {
    my $self = $_[0];

    # make sure that the cart contains something that costs something.  since
    # this check should have been done above, we die hardcore here.
    my $cart = $self->cart;
    die "Constraints not met: cart && cart->has_items && cart->has_total > 0.00.\n"
        unless $cart && $cart->has_items && $cart->total > 0.00;

    # we have to have this later
    my $dbh = DW::Pay::get_db_writer()
        or return $self->temp_error( 'nodb' );

    # okay, let's build the hash we're going to send to PayPal.  first up, the
    # basic stuff that we're always going to send.
    my @req = (
        # yes, this is a purchase
        paymentaction => 'Sale',

        # how much it costs.  no tax or shipping.
        amt           => $cart->display_total,
        itemamt       => $cart->display_total,
        taxamt        => '0.00',
        noshipping    => 1,

        # do not allow the buyer to send us custom notes
        allownote     => 0,

        # where PayPal can send people back to
        cancelurl     => "$LJ::SITEROOT/shop/pp_cancel",
        returnurl     => "$LJ::SITEROOT/shop/pp_confirm",

        # custom data we send to reference this cart
        custom        => join( '-', ( $cart->id, $cart->display_total ) ),
    );

    # now we have to stick in data for each of the items in the cart
    my $cur = 0;
    foreach my $item ( @{ $cart->items } ) {
        push @req, "L_NAME$cur"   => $item->class_name,
                   "L_DESC$cur"   => $item->short_desc,
                   "L_NUMBER$cur" => $cart->id . "-" . $item->id,
                   "L_QTY$cur"    => 1,
                   "L_AMT$cur"    => $item->cost;
        $cur++;
    }

    # now we can pass this off to PayPal...
    my $res = $self->_pp_req( 'SetExpressCheckout', @req );
    return $self->error( 'paypal.notoken' )
        unless defined $res && exists $res->{token};

    # now store this in the db
    $dbh->do(
        q{INSERT INTO pp_tokens (ppid, inittime, touchtime, cartid, token, status)
          VALUES (NULL, UNIX_TIMESTAMP(), UNIX_TIMESTAMP(), ?, ?, 'init')},
        undef, $cart->id, $res->{token}
    );
    return $self->error( 'dberr', errstr => $dbh->errstr )
        if $dbh->err;

    # and finally, this is the URL!
    return $LJ::PAYPAL_CONFIG{url} . $res->{token};
}


# confirm_order()
#
# does the final capture process to tell PayPal that we want to charge the
# user for their payment.
sub confirm_order {
    my $self = $_[0];

    # ensure status is 'init'
    return $self->error( 'paypal.engbadstate' )
        unless $self->status eq 'init';

    # now ensure we can get jobs sent off
    my $sh = LJ::theschwartz()
        or return $self->temp_error( 'paypal.noschwartz' );

    # now we have to call out to PayPal to get some details on this order
    # and make sure that the user has finished the process and isn't just
    # trying to fake it
    my $res = $self->_pp_req(
        'GetExpressCheckoutDetails',
        token => $self->token
    );
    return $self->temp_error( 'paypal.flownotfinished' )
        unless $res && $res->{payerid};

    # store whatever it gives us
    $self->payerid( $res->{payerid} );
    $self->firstname( $res->{firstname} );
    $self->lastname( $res->{lastname} );
    $self->email( $res->{email} );

    # okay, schedule the job to actually do the right thing
    my $job = TheSchwartz::Job->new(
        funcname => 'DW::Worker::Payment',
        arg => { ppid => $self->ppid }
    );
    my $h = $sh->insert( $job );
    return $self->temp_error( 'paypal.schwartzinsert' )
        unless $h;

    # and mark this paypal item as processing
    $self->status( 'queued' );

    return 1;
}


################################################################################
## internal methods, nobody else should be calling these
################################################################################


# sends a request to PayPal.  pretty straightforward.  handles logging.
sub _pp_req {
    my ( $self, $method, @args ) = @_;

    # put in the standard stuff
    push @args, method    => $method,
                version   => '56.0',
                user      => $LJ::PAYPAL_CONFIG{user},
                pwd       => $LJ::PAYPAL_CONFIG{password},
                signature => $LJ::PAYPAL_CONFIG{signature};

    my $req = HTTP::Request->new( 'POST', $LJ::PAYPAL_CONFIG{api_url} );
    $req->content_type( 'application/x-www-form-urlencoded' );

    # we have to do this to preserve the order of items, as PayPal's API seems to
    # require things to be ordered
    my @req;
    while ( my ( $key, $val ) = splice @args, 0, 2 ) {
        push @req, uc( LJ::eurl( $key ) ) . '=' . LJ::eurl( $val );
    }
    my $reqct = join( '&', @req );
    $req->content( $reqct );

    my $ua = LJ::get_useragent( role => 'paypal', timeout => 20 );
    $ua->agent( 'DW-PayPal-Engine/1.0' );

    my $res = $ua->request( $req );
    if ( $res->is_success ) {
        # this funging is just to get the keys lowercase
        my $tmp = {
            map { LJ::durl( $_ ) }
                map { split( /=/, $_ ) }
                    split( /&/, $res->content )
        };
        my $resh = {};
        $resh->{lc $_} = $tmp->{$_} foreach keys %$tmp;

        # best case logging, don't fail if we had an error logging, because we've
        # already done the PayPal logic and failing on logging could lead to us
        # taking money but not crediting accounts, etc ...
        if ( ref $self && ( my $ppid = $self->ppid ) ) {
            my $dbh = DW::Pay::get_db_writer();
            if ( my $dbh ) {
                $dbh->do( q{
                        INSERT INTO pp_log (ppid, transtime, req_content, res_content)
                        VALUES (?, UNIX_TIMESTAMP(), ?)
                    }, undef, $ppid, $reqct, $res->content );
            }
        }

        return $resh;
    } else {
        return $self->temp_error( 'paypal.connection' );
    }
}


# accessors
sub ppid { $_[0]->{ppid} }
sub cart { $_[0]->{cart} }
sub token { $_[0]->{token} }
sub inittime { $_[0]->{inittime} }
sub touchtime { $_[0]->{touchtime} }


# mutable accessors
sub status { _getset( $_[0], 'status', $_[1] ) }
sub payerid { _getset( $_[0], 'payerid', $_[1] ) }
sub firstname { _getset( $_[0], 'firstname', $_[1] ) }
sub lastname { _getset( $_[0], 'lastname', $_[1] ) }
sub email { _getset( $_[0], 'email', $_[1] ) }


# meta accessor
sub _getset {
    my ( $self, $key, $newval ) = @_;
    return $self->{$key} unless defined $newval;

    my $dbh = DW::Pay::get_db_writer()
        or die 'no database';
    $dbh->do(
        qq{UPDATE pp_tokens SET $key = ?, touchtime = UNIX_TIMESTAMP() WHERE ppid = ?},
        undef, $newval, $self->ppid
    );
    die $dbh->errstr
        if $dbh->err;

    return $self->{$key} = $newval;
}


1;
