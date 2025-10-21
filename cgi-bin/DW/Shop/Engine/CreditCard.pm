#!/usr/bin/perl
#
# DW::Shop::Engine::CreditCard
#
# Interfaces to our credit card processing service.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Shop::Engine::CreditCard;

use strict;
use Carp qw/ croak confess /;
use Digest::MD5 qw/ md5_hex /;
use Storable qw/ nfreeze thaw /;

use base qw/ DW::Shop::Engine /;

# new( $cart )
#
# instantiates a new engine for the given cart
sub new {
    return bless { cart => $_[1] }, $_[0];
}

# checkout_url()
#
# this is simple, send them to the page for entering their credit card information
sub checkout_url {
    my $self = $_[0];

    # make sure that the cart contains something that costs something.  since
    # this check should have been done above, we die hardcore here.
    my $cart = $self->cart;
    die "Constraints not met: cart && cart->has_items && cart->total_cash > 0.00.\n"
        unless $cart && $cart->has_items && $cart->total_cash > 0.00;

    # and, just in case something terrible happens, make sure our state is good
    die "Cart not in valid state!\n"
        unless $cart->state == $DW::Shop::STATE_OPEN;

    # return URL to cc entry
    return "$LJ::SITEROOT/shop/entercc";
}

# setup_transaction( ...many options... )
#
# sets up a transaction row in the database, also dispatches the gearman task to
# actually attempt to charge the user.
#
# THIS MUST NOT SAVE THE CREDIT CARD NUMBER TO ANY DATABASE.
#
sub setup_transaction {
    my ( $self, %in ) = @_;

    # insert the data we can in the db
    my $dbh = DW::Pay::get_db_writer()
        or die "Unable to get database handle.\n";
    $dbh->do(
        q{INSERT INTO cc_trans (cctransid, cartid, firstname, lastname,
            street1, street2, city, state, country, zip, phone, ipaddr, expmon, expyear, ccnumhash)
          VALUES (NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)},
        undef,
        (
            map { $in{$_} }
                qw/ cartid firstname lastname street1 street2 city state country zip phone ip expmon expyear /
        ),
        md5_hex( $in{ccnum} . $in{cvv2} )
    );
    die "Database error: " . $dbh->errstr . "\n"
        if $dbh->err;

    # now we have a basic row
    $in{cctransid} = $dbh->{mysql_insertid};

    # dispatch this item...
    my $gc = LJ::gearman_client()
        or die "Unable to get gearman client.\n";
    my $ref = $gc->dispatch_background(
        'dw_creditcard_charge',
        nfreeze( \%in ),
        { uniq => $in{cctransid} }
    );
    die "Unable to insert Gearman job.\n"
        unless $ref;

    # update our row from above so we have it later, avoiding columns
    # the worker may have already updated.
    $dbh->do( 'UPDATE cc_trans SET dispatchtime = UNIX_TIMESTAMP() WHERE cctransid = ?',
        undef, $in{cctransid} );
    $dbh->do(
        'UPDATE cc_trans SET gctaskref = ?, jobstate = ? WHERE cctransid = ? AND jobstate IS NULL',
        undef, $ref, 'queued', $in{cctransid}
    );
    return $in{cctransid};
}

# get_transaction( cctransid )
#
# returns a transaction row for a given id.
sub get_transaction {
    my ( $self, $cctransid ) = @_;

    my $dbh = DW::Pay::get_db_writer()
        or die "Unable to get database handle.\n";

    # FIXME: "SELECT *" is for sad making :(
    my $row =
        $dbh->selectrow_hashref( 'SELECT * FROM cc_trans WHERE cctransid = ?', undef, $cctransid );
    die "Database error: " . $dbh->errstr . "\n"
        if $dbh->err;

    # if this task has no gctaskref it's already finished or never got one, so
    # just return the row as is
    return $row unless $row->{gctaskref};

    # now, if it's queued, try to get some state on it
    my $gc = LJ::gearman_client()
        or return $row;
    my $js = $gc->get_status( $row->{gctaskref} );

    # if the job is known to the server, that means it's in the queue somewhere, so we are
    # okay to just return whatever state the row has (which should be 'queued')
    return $row if $js && $js->known;
    return $row unless $row->{jobstate} eq 'queued';

    # if we get here and it says 'queued', that means that we think the job is in Gearman,
    # but by this point we know it's not. we need to check the database again to see if
    # the state has been updated. this prevents a race condition we've sometimes seen.
    my $row2 =
        $dbh->selectrow_hashref( 'SELECT * FROM cc_trans WHERE cctransid = ?', undef, $cctransid );
    die "Database error: " . $dbh->errstr . "\n"
        if $dbh->err;

    # now, if the job is not known, and we are still 'queued', something terrible happened
    # like the worker crashed or the gearman server crashed
    if ( $row2->{jobstate} eq 'queued' ) {
        $row2->{jobstate} = 'internal_failure';
        $row2->{joberr}   = 'Task no longer known to Gearman.';
        $dbh->do(
            'UPDATE cc_trans SET jobstate = ?, joberr = ?, gctaskref = NULL WHERE cctransid = ?',
            undef, $row2->{jobstate}, $row2->{joberr}, $cctransid );
        die $dbh->errstr if $dbh->err;
    }

    return $row2;
}

# try_capture( ...many values... )
#
# given an input of some values, try to capture funds from the processor.  this
# uses a hook so that local sites can implement their own payment processing
# logic...
#
# note that it is important that you don't actually save the credit card number
# anywhere on your servers unless you are doing PCI compliance.
#
# to repeat: DO NOT SAVE CREDIT CARD NUMBERS TO DISK.  well, at least not in
# the US.  if you're in another country, your own rules apply.
#
sub try_capture {
    my ( $self, %in ) = @_;

    die "Unable to capture funds: no credit card processor loaded.\n"
        unless LJ::Hooks::are_hooks('creditcard_try_capture');

    # first capture the points if we have any to do
    return ( 0, 'Failed to capture points to complete order.' )
        unless $self->try_capture_points;

    # this hook is supposed to try to capture the funds.  return value is a
    # list: ( $code, $message ).  code is one of 0 (declined), 1 (success).
    # message is optional and if saved will be recorded as the status message.
    my ( $res, $msg ) = LJ::Hooks::run_hook( creditcard_try_capture => ( $self, \%in ) );

    # if the capture failed, refund the points
    $self->refund_captured_points
        unless $res;

    # the person who called us is responsible for setting up cart and engine
    # status based on the results.  improvement: maybe move all that logic
    # up to here so the workers are really small?
    return ( $res, $msg );
}

# accessors
sub cart      { $_[0]->{cart} }
sub cctransid { $_[0]->cart->{cctransid} }

1;
