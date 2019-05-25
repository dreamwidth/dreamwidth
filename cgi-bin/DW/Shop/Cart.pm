#!/usr/bin/perl
#
# DW::Shop::Cart
#
# Encapsulates a shopping cart for a user.  Handles loading, saving, modifying
# and all other actions of a shopping cart.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009-2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Shop::Cart;

use strict;
use Carp qw/ croak confess /;
use Storable qw/ nfreeze thaw /;

use DW::Shop;

# returns a created cart for a given shop
sub get {
    my ( $class, $shop ) = @_;

    # see if the shop has a user or if it's anonymous
    my ( $u, $sql, @bind );
    if ( $shop->anonymous ) {

        # if they don't have a unique cookie and they're anonymous, we aren't
        # presently equipped to let them shop
        my $uniq = LJ::UniqCookie->current_uniq
            or return undef;

        $sql  = 'uniq = ? AND userid IS NULL';
        @bind = ($uniq);

    }
    else {
        $u = $shop->u
            or confess 'shop has no user object';

        # return this cart if loaded already
        return $u->{_cart} if $u->{_cart};

        # faaail, have to load it
        $sql  = 'userid = ?';
        @bind = ( $u->id );
    }

    # see if they had one in the database
    my $dbh = LJ::get_db_writer()
        or return undef;
    my $dbcart = $dbh->selectrow_hashref(
        qq{SELECT cartblob
           FROM shop_carts
           WHERE $sql AND state = ?
           ORDER BY starttime DESC
           LIMIT 1},
        undef, @bind, $DW::Shop::STATE_OPEN
    );

    # if we got something, thaw the blob and return
    if ($dbcart) {
        my $cart = $class->_build( thaw( $dbcart->{cartblob} ) );
        if ($u) {
            $u->{_cart} = $cart;
        }
        return $cart;
    }

    # no existing cart, so build a new one \o/
    return $class->new_cart($u);
}

# returns a new cart given a cartid
sub get_from_cartid {
    my ( $class, $cartid ) = @_;
    return undef
        unless defined $cartid && $cartid > 0;

    # see if they had one in the database
    my $dbh = LJ::get_db_writer()
        or return undef;
    my $dbcart = $dbh->selectrow_hashref(
        qq{SELECT cartblob
           FROM shop_carts WHERE cartid = ?},
        undef, $cartid
    );
    return undef unless $dbcart;

    # if we got something, thaw the blob and return
    return $class->_build( thaw( $dbcart->{cartblob} ) );
}

# returns a new cart given an ordernum
sub get_from_ordernum {
    my ( $class, $ordernum ) = @_;
    my ( $cartid, $authcode );

    ( $cartid, $authcode ) = ( $1 + 0, $2 )
        if $ordernum =~ /^(\d+)-(.+)$/;
    return undef
        unless $cartid && $cartid > 0;
    return undef
        unless $authcode && length($authcode) == 20;

    # see if they had one in the database
    my $cart = $class->get_from_cartid($cartid);
    return undef
        unless $cart && $cart->authcode eq $authcode;

    # all matches, so return this cart
    return $cart;
}

# returns a new cart given an invite code
# if scalar ref 'itemidref' is passed, store the itemid for the invite code in it
sub get_from_invite {
    my ( $class, $code, %opts ) = @_;

    my $itemidref = $opts{itemidref};

    my ($acid) = DW::InviteCodes->decode($code);
    return undef
        unless defined $acid && $acid > 0;

    my $dbh = LJ::get_db_writer()
        or return undef;
    my $dbret = $dbh->selectrow_hashref(
        qq{SELECT cartid, itemid
           FROM shop_codes WHERE acid = ?},
        undef, $acid
    );
    return undef unless $dbret;

    $$itemidref = $dbret->{itemid} if ref $itemidref eq 'SCALAR';
    return $class->get_from_cartid( $dbret->{cartid} );
}

# creating a new cart implicitly activates.  just so you know.  this function
# will build a new empty cart for the user.  but user is optional and we will
# build a cart for the current uniq.
sub new_cart {
    my ( $class, $u ) = @_;
    $u = LJ::want_user($u);

    my $cartid = LJ::alloc_global_counter('H')
        or return undef;

    # this is a blank cart containing no items
    my $cart = {
        cartid        => $cartid,
        starttime     => time(),
        userid        => $u ? $u->id : undef,
        ip            => LJ::get_remote_ip(),
        state         => $DW::Shop::STATE_OPEN,
        items         => [],
        total_cash    => 0.00,
        total_points  => 0,
        nextscan      => 0,
        authcode      => LJ::make_auth_code(20),
        paymentmethod => 0,                        # we don't have a payment method yet
        email         => undef,                    # we don't have an email yet
    };

    # if uniq undef, hash definition is totally wrecked, so set this separately
    $cart->{uniq} = LJ::UniqCookie->current_uniq;

    # now, delete any old carts we don't need
    my $dbh = LJ::get_db_writer()
        or return undef;
    if ( defined $cart->{userid} ) {
        $dbh->do( q{UPDATE shop_carts SET state = ? WHERE userid = ? AND state = ?},
            undef, $DW::Shop::STATE_CLOSED, $cart->{userid}, $DW::Shop::STATE_OPEN );
        croak $dbh->errstr if $dbh->err;
    }
    if ( defined $cart->{uniq} ) {
        $dbh->do( q{UPDATE shop_carts SET state = ? WHERE uniq = ? AND state = ?},
            undef, $DW::Shop::STATE_CLOSED, $cart->{uniq}, $DW::Shop::STATE_OPEN );
        croak $dbh->errstr if $dbh->err;
    }

    # build this into an object and activate it
    $cart = $class->_build($cart);

    # now persist the cart
    $cart->save;
    $u->{_cart} = $cart if $u;

    DW::Stats::increment( 'dw.shop.cart.new', 1, [ 'anonymous:' . ( $u ? 'no' : 'yes' ) ] );

    # we're done
    return $cart;
}

# returns all carts that the given user has ever had
# can pass 'finished' opt which will omit carts in the OPEN, CLOSED, or
# CHECKOUT states
sub get_all {
    my ( $class, $u, %opts ) = @_;
    $u = LJ::want_user($u);

    my $extra_sql =
        $opts{finished}
        ? " AND state NOT IN ($DW::Shop::STATE_OPEN,"
        . " $DW::Shop::STATE_CLOSED,"
        . " $DW::Shop::STATE_CHECKOUT)"
        : "";

    my $dbh = LJ::get_db_writer()
        or return undef;
    my $sth = $dbh->prepare("SELECT cartblob FROM shop_carts WHERE userid = ?$extra_sql");
    $sth->execute( $u->id );

    my @carts = ();
    while ( my $cart = $sth->fetchrow_hashref ) {
        push @carts, $class->_build( thaw( $cart->{cartblob} ) );
    }

    return @carts;
}

# saves the current cart to the database, returns 1/0
sub save {
    my ( $self, %opts ) = @_;

    # we store the payment method id in the db
    my $paymentmethod_id = $DW::Shop::PAYMENTMETHODS{ $self->paymentmethod }->{id} || 0;

    # toss in the database
    my $dbh = LJ::get_db_writer()
        or return undef;
    $dbh->do(
q{REPLACE INTO shop_carts (userid, cartid, starttime, uniq, state, nextscan, authcode, email, paymentmethod, cartblob)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)},
        undef,
        ( map { $self->{$_} } qw/ userid cartid starttime uniq state nextscan authcode email / ),
        $paymentmethod_id, nfreeze($self)
    );

    # bail if error
    return 0 if $dbh->err;
    return 1;
}

# returns an engine for this cart
sub engine {
    my $self = $_[0];

    return $self->{_engine} ||= DW::Shop::Engine->get( $self->paymentmethod => $self );
}

# returns the number of items in this cart
sub num_items {
    my $self = $_[0];

    return scalar @{ $self->{items} || [] };
}

# returns 1/0 if this cart has any items in it
sub has_items {
    my $self = $_[0];

    return $self->num_items > 0 ? 1 : 0;
}

# add an item to the shopping cart, returns 1/0
sub add_item {
    my ( $self, $item ) = @_;
    return unless $self && $item;

    die "Attempted to alter cart not in OPEN state.\n"
        unless $self->state == $DW::Shop::STATE_OPEN;

    # tell the item who we are
    $item->cartid( $self->id );

    # make sure this item is allowed to be added
    my $error;
    unless (
        $item->can_be_added( errref => \$error, user_confirmed => delete $item->{user_confirmed} ) )
    {
        return ( 0, $error );
    }

    # iterate over existing items to see if any conflict
    foreach my $it ( @{ $self->items } ) {
        if ( my $rv = $it->conflicts($item) ) {

            # this return value is so messed up... WTB exceptions
            return ( 0, $rv );
        }
    }

    # construct a new, unique id for this item
    my $itid = LJ::alloc_global_counter('I')
        or return ( 0, 'Failed to allocate item counter.' );
    $item->id($itid);

    # looks good, so let's add it...
    push @{ $self->items }, $item;
    $self->recalculate_costs;

    # now call out to the hook system in case anybody wants to munge with us
    LJ::Hooks::run_hooks( 'shop_cart_added_item', $self, $item );

    # save to db and return
    $self->_touch;
    $self->save || return ( 0, 'Unable to save cart.' );
    return 1;
}

# removes an item from this cart by id
sub remove_item {
    my ( $self, $id, %opts ) = @_;
    return unless $self && $id;

    die "Attempted to alter cart not in OPEN state.\n"
        unless $self->state == $DW::Shop::STATE_OPEN;

    my ( $removed, $out ) = ( undef, [] );
    foreach my $it ( @{ $self->items } ) {
        if ( $it->id == $id ) {

            # some items are noremove items
            if ( $it->noremove && !$opts{force} ) {
                push @$out, $it;
                next;
            }

            # advise that we removed an item from the cart
            die "Attempted to remove two items in one pass with id $id.\n"
                if defined $removed;
            $removed = $it;
        }
        else {
            push @$out, $it;
        }
    }
    $self->{items} = $out;

    # now recalculate the costs and save
    $self->recalculate_costs;
    $self->_touch;
    $self->save;

    # now run the hook, this is later so that we've updated the cart already
    LJ::Hooks::run_hooks( 'shop_cart_removed_item', $self, $removed );

    return 1;
}

sub recalculate_costs {
    my $self = $_[0];

    # if we're not in the OPEN state, do not recalculate.  the prices are fixed.
    return unless $self->state == $DW::Shop::STATE_OPEN;

    my ( $has_points, $max_points ) = ( 0, 0 );
    if ( $self->userid ) {
        my $u = LJ::load_userid( $self->userid );
        $has_points = $u->shop_points;
    }

    # we have to determine the total cost of the order first so we can do the
    # minimum order size calculations later
    ( $self->{total_points}, $self->{total_cash} ) = ( 0, 0.00 );
    foreach my $item ( @{ $self->items } ) {
        $self->{total_cash} += $item->paid_cash( $item->cost_cash );
        $item->paid_points(0);
        $max_points += $item->cost_points;
    }

    # if the user has no points, we're done
    return unless $has_points;

    # now, if we're short on points, the maximum we can use is based on the
    # minimum cash order size
    if ( $has_points < $max_points ) {

        # x10 to convert from USD to points
        my $cutoff = $max_points - ( $DW::Shop::MIN_ORDER_COST * 10 );

        # now we effectively constrain the ceiling of how many points the user
        # has to the point that makes the cash equivalent $3.00
        $has_points = $cutoff
            if $has_points > $cutoff;
    }

    # second loop has to iterate and actually adjust the point/cash balances
    foreach my $item ( @{ $self->items } ) {

        # in some cases, we have items that cost no points, those items
        # we can just ignore and skip
        next unless $item->cost_points;

        # start deducting items from points until one goes negative
        $has_points -= $item->cost_points;

        # if positive, the item was paid for by points entirely
        if ( $has_points >= 0 ) {
            $item->paid_cash(0.00);
            $item->paid_points( $item->cost_points );

            $self->{total_cash} -= $item->cost_cash;
            $self->{total_points} += $item->cost_points;

            # and last if we're at 0 points left
            last if $has_points == 0;

        }
        else {
            my $cash = -$has_points;
            $item->paid_cash( $cash / 10 );
            $item->paid_points( $item->cost_points - $cash );

            $self->{total_cash} -= $item->cost_cash - $item->paid_cash;
            $self->{total_points} += $item->paid_points;

            # and this means we're done
            last;
        }
    }
}

# given an itemid that's in this cart, return it
sub get_item {
    my ( $self, $id ) = @_;

    foreach my $it ( @{ $self->items } ) {
        return $it if $it->id == $id;
    }

    return undef;
}

# get/set state
sub state {
    my ( $self, $newstate ) = @_;
    return $self->{state} unless defined $newstate;
    return $self->{state} if $self->{state} == $newstate;

    # alert the items that the cart's state has changed, this allows items to do things
    # that happen when the state changes.
    $_->cart_state_changed($newstate) foreach @{ $self->items };

    LJ::Hooks::run_hooks( 'shop_cart_state_change', $self, $newstate );
    DW::Stats::increment(
        'dw.shop.cart.state_change',
        1,
        [
            'from_state:' . $DW::Shop::STATE_NAMES{ $self->{state} },
            'to_state:' . $DW::Shop::STATE_NAMES{$newstate}
        ]
    );

    $self->_notify_buyer_paid if $newstate == $DW::Shop::STATE_PROCESSED;

    $self->{state} = $newstate;
    $self->save;

    return $self->{state};
}

# get/set payment method
sub paymentmethod {
    my ( $self, $newpaymentmethod ) = @_;

    return $self->{paymentmethod}
        unless defined $newpaymentmethod;

    $self->{paymentmethod} = $newpaymentmethod;
    $self->save;

    return $self->{paymentmethod};
}

# payment method the user should be aware of
sub paymentmethod_visible {
    my $self = $_[0];

    my $paymentmethod = $self->{paymentmethod};
    return $paymentmethod unless $paymentmethod eq "checkmoneyorder";
    return ( $self->total_cash == 0 ) ? "points" : $paymentmethod;
}

# get/set email address
sub email {
    my ( $self, $newemail ) = @_;

    return $self->{email}
        unless defined $newemail;

    $self->{email} = $newemail;
    $self->save;

    return $self->{email};
}

################################################################################
## read-only accessor methods
################################################################################

sub id           { $_[0]->{cartid} }
sub userid       { $_[0]->{userid} }
sub starttime    { $_[0]->{starttime} }
sub age          { time() - $_[0]->{starttime} }
sub items        { $_[0]->{items} ||= [] }
sub ip           { $_[0]->{ip} }
sub uniq         { $_[0]->{uniq} }
sub nextscan     { $_[0]->{nextscan} }
sub authcode     { $_[0]->{authcode} }
sub total_points { $_[0]->{total_points} + 0 }
sub ordernum     { $_[0]->{cartid} . '-' . $_[0]->{authcode} }

# this has to work for both old items (pre-points) and new ones
sub total_cash {
    my $self = $_[0];
    return $self->{total} + 0.00 if exists $self->{total};
    return $self->{total_cash} + 0.00;
}

# returns the total in a displayed format
sub display_total {
    my $self = $_[0];
    if ( $self->total_cash && $self->total_points ) {
        return sprintf( '$%0.2f USD and %d points', $self->total_cash, $self->total_points );
    }
    elsif ( $self->total_cash ) {
        return sprintf( '$%0.2f USD', $self->total_cash );
    }
    elsif ( $self->total_points ) {
        return sprintf( '%d points', $self->total_points );
    }
    else {
        return 'free';
    }
}

sub display_total_cash   { sprintf( '$%0.2f USD', $_[0]->total_cash ) }
sub display_total_points { sprintf( '%d points',  $_[0]->total_points ) }

################################################################################
## internal cart methods
################################################################################

# turns a hashref cart into a cart object
sub _build {
    my ( $class, $cart ) = @_;
    ref $cart eq 'HASH' or return $cart;

    # simply blesses ... although in the future we might do some sanity checking
    # here to make sure we have good data, if that proves to be necessary.
    return bless $cart, $class;
}

# called to update our access time, this is mostly an internal method, but anybody
# that has reason to can call it;  note that this needs to be called before a save
sub _touch {
    $_[0]->{starttime} = time;
}

# let the cart owner know that their purchase has just gone through.
sub _notify_buyer_paid {
    my $self = $_[0];

    my $u = LJ::load_userid( $self->{userid} );

    my @payment_methods;
    push @payment_methods, '$' . $self->total_cash . ' USD'
        if $self->total_cash;
    push @payment_methods, $self->total_points . ' points'
        if $self->total_points;

    my $itemlist = join( "\n", map { "  * " . $_->short_desc( nohtml => 1 ) } @{ $self->items } );

    LJ::send_mail(
        {
            to       => $self->email,
            from     => $LJ::ACCOUNTS_EMAIL,
            fromname => $LJ::SITENAME,
            subject =>
                LJ::Lang::ml( "shop.email.processed.subject", { sitename => $LJ::SITENAME } ),
            body => LJ::Lang::ml(
                "shop.email.processed.body",
                {
                    touser     => LJ::isu($u) ? $u->display_name : $self->email,
                    price      => join( ", ", @payment_methods ),
                    itemlist   => $itemlist,
                    receipturl => "$LJ::SITEROOT/shop/receipt?ordernum=" . $self->ordernum,
                    sitename   => $LJ::SITENAME,
                }
            ),
        }
    ) unless $LJ::T_SUPPRESS_EMAIL;
}

1;
