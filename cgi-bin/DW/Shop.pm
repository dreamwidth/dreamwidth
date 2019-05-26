#!/usr/bin/perl
#
# DW::Shop
#
# General helper class that defines a shopping session and generally facilitate
# a user interacting with stuff.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Shop;

use strict;
use Carp qw/ croak confess /;

use DW::Shop::Cart;
use DW::Shop::Engine;

use LJ::ModuleLoader;
LJ::ModuleLoader->require_subclasses("DW::Shop::Item");

# constants across the site
our $MIN_ORDER_COST = 3.00;    # cost in USD minimum.  this only comes into affect if
                               # a user is trying to check out an order that costs
                               # less than this.

# variables we maintain
our $STATE_OPEN        = 1;    # open carts - user can still modify
our $STATE_CHECKOUT    = 2;    # carts have gone through checkout (COMPLETED checkout)
our $STATE_PEND_PAID   = 3;    # waiting on payment confirmation (eCheck?)
our $STATE_PAID        = 4;    # payment received but cart hasn't been processed
our $STATE_PROCESSED   = 5;    # we have received payment for this cart
our $STATE_PEND_REFUND = 6;    # refund is approved but unissued
our $STATE_REFUNDED    = 7;    # we have refunded this cart and reversed it
our $STATE_CLOSED      = 8;    # carts can go from OPEN -> CLOSED
our $STATE_DECLINED    = 9;    # payment entity declined the fundage

# state names, just for helping
our %STATE_NAMES = (
    1 => 'open',
    2 => 'checkout',
    3 => 'pend_paid',
    4 => 'paid',
    5 => 'processed',
    6 => 'pend_refund',
    7 => 'refunded',
    8 => 'closed',
    9 => 'declined'
);

# documentation of valid state transitions...
#
#   OPEN -> CHECKOUT     user has decided to purchase this and we have sent the
#                        payment information to PayPal or Google, but we haven't
#                        heard back on what's going on
#
#   CHECKOUT -> PEND_PAID  PP/GC tells us that the user is paying through some
#                          method that won't let us get the money yet, so we will
#                          have to hold until we hear back again
#
#   PEND_PAID -> PAID    both of these transitions indicate that the user has
#   CHECKOUT -> PAID     really given us the money.  i.e., we've got cash in hand
#                        and we are ready to actually process the cart.
#
#   PAID -> PROCESSED    after we have processed the cart (i.e., granted the paid
#                        time, given the points, etc.)  this lets us know that the
#                        cart is now 'done'.
#
#   PROCESSED -> PEND_REFUND  the user wants a refund and the refund has been
#                             approved.  this is basically a reverse-process step.
#
#   PEND_REFUND -> REFUNDED   once the processing has been complete and we have
#                             unapplied everything that we can, we set state.
#
#   OPEN -> CLOSED       this state is only used if the user has timed out a
#                        cart.  i.e., it hasn't been touched in a while so we
#                        decide the user isn't coming back.
#
#   PEND_PAID -> DECLINED  happens when we try to capture funds from a remote
#                          entity and they decline for some reason.
#
# any other state transition is hereby considered null and void.

# keys are the names of the various payment methods as passed by the cart widget drop-down
# values are hashrefs with id (the integer value that is stored in the 'paymentmethod'
# field in the db) and class (the name of the DW::Shop::Engine class)
our %PAYMENTMETHODS = (
    paypal => {
        id    => 1,
        class => 'PayPal',
    },
    checkmoneyorder => {
        id    => 2,
        class => 'CheckMoneyOrder',
    },
    creditcardpp => {
        id    => 3,
        class => 'CreditCardPP',
    },
    gco => {
        id    => 4,
        class => 'GoogleCheckout',
    },
    creditcard => {
        id    => 5,
        class => 'CreditCard',
    },
);

# called to return an instance of the shop; auto-determines if we have a
# remote user and uses that, else, just returns an anonymous shop
sub get {
    my ($class) = @_;

    # easy mode: if we have a remote then we can just toss this into the
    # bucket and have it be used; this trick works because get_remote and
    # such always return the same actual hash within a request
    if ( my $u = LJ::get_remote() ) {
        return $u->{_shop} ||= bless { userid => $u->id }, $class;
    }

    # no remote, so let's note that
    return bless { anon => 1 }, $class;
}

# returns an active cart, if the user has one
sub cart {
    my ($self) = @_;

    return DW::Shop::Cart->get($self);
}

# builds a new cart for the user (throws away existing active)
sub new_cart {
    my ($self) = @_;

    return DW::Shop::Cart->new_cart($self);
}

# gets a link to the active user; this is done this way with a load_userid call
# to prevent circular references.  (we could just make it a weak reference...?)
# FIXME: explore if LJ uses weak references anywhere and if so we can use them
# to store a weakened-$u in $self in initialize()
sub u {
    return undef if $_[0]->{anon} || !$_[0]->{userid};
    return LJ::load_userid( $_[0]->{userid} );
}

# true if this is an anonymous shopping session
sub anonymous {
    return $_[0]->{anon} ? 1 : 0;
}

# returns a text error string if the remote is not allowed to use the
# shop/payment system, undef means they're allowed
sub remote_sysban_check {

    # do sysban checks:
    if ( LJ::sysban_check( 'pay_uniq', LJ::UniqCookie->current_uniq ) ) {
        return BML::ml( 'error.blocked',
            { blocktype => "computer", email => $LJ::ACCOUNTS_EMAIL } );
    }
    elsif ( my $remote = LJ::get_remote() ) {
        if ( LJ::sysban_check( 'pay_user', $remote->user ) ) {
            return BML::ml( 'error.blocked',
                { blocktype => "account", email => $LJ::ACCOUNTS_EMAIL } );
        }
        elsif ( LJ::sysban_check( 'pay_email', $remote->email_raw ) ) {
            return BML::ml( 'error.blocked',
                { blocktype => "email address", email => $LJ::ACCOUNTS_EMAIL } );
        }
    }

    # looks good
    return undef;
}

################################################################################
## LJ::User methods
################################################################################

package LJ::User;

use Carp qw/ confess /;

# returns the shop on a user
sub shop {
    my $shop = $_[0]->{_shop}
        or confess 'tried to get shop without calling DW::Shop->initialize()';
    return $shop;
}

1;
