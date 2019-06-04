#!/usr/bin/perl
#
# DW::VirtualGiftTransaction - Support virtual gift transactions
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2012-2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::VirtualGiftTransaction;

use strict;
use warnings;

use DW::Shop::Cart;
use DW::VirtualGift;

# Because events use this module, Perl warns about redefined subroutines.
{
    no warnings 'redefine';
    use LJ::Event::VgiftDelivered;
}

# IMPLEMENTATION: a blessed hashref with some or all of the following keys:
#
# From database: transid, rcptid, vgiftid, buyerid, cartid, delivery_t,
#                accepted, delivered, expired
#
# From associated shop cart: anon, from, reason, from_text
#
# For convenience: id, user, vgift, buyer, timestamp (more useful forms)
#
# Uniqueness of a transaction is determined from rcptid + transid.
#
#
# USAGE:
#
# DW::VirtualGiftTransaction->load( user => u/uid, id => transid );
# -- loads an existing transaction, returns object
#
# DW::VirtualGiftTransaction->save( user => u/uid, vgift => vgiftid );
# -- saves a new transaction, returns transaction ID
#
# DW::VirtualGiftTransaction->list( user => u/uid, profile => 1/0 );
# -- returns the list of transaction objects for the given user
#
#
# Methods for transaction objects:
#
# Properties: id, u, url
# Queries: is_delivered, is_accepted, is_expired, is_anonymous
# Actions: remove, expire, accept, deliver, notify_delivered
# Display: view, from_html, from_text

sub save {
    my ( $class, %opts ) = @_;

    # opts: user => (u or userid) - mandatory
    #       vgift => (obj or id) - mandatory
    #       cartid => (cartid) - optional
    #       buyer => (u or userid) - optional
    #       time => (epoch seconds) - optional (defaults to current time)

    my $vg    = $opts{vgift} or return;
    my $vgift = ref $vg ? $vg : DW::VirtualGift->new($vg);
    return unless $vgift && $vgift->id;

    my $u       = LJ::want_user( $opts{user} ) or return;
    my $id      = LJ::alloc_user_counter( $u, 'V' ) or return;
    my $secs    = $opts{time} || localtime;
    my $buyer   = LJ::want_user( $opts{buyer} );
    my $buyerid = $buyer ? $buyer->id : 0;

    $u->do(
        'INSERT INTO vgift_trans (transid, rcptid, vgiftid, buyerid,'
            . ' cartid, delivery_t) VALUES (?, ?, ?, ?, ?, ?)',
        undef, $id, $u->id, $vgift->id, $buyerid, $opts{cartid}, $secs
    );
    die $u->errstr if $u->err;

    # update the vgift_counts table
    $vgift->mark_sold;

    # memcache expiration for list of all transactions
    LJ::MemCache::delete( $class->_transaction_list_memkey($u) );

    return $id;    # not object
}

sub list {
    my ( $class, %opts ) = @_;
    my $u = LJ::want_user( $opts{user} ) or return;

    my $memkey = $class->_transaction_list_memkey($u);
    my $data   = LJ::MemCache::get($memkey);

    unless ( defined $data ) {

        # Note: we pretend undelivered gifts don't exist yet.
        $data = $u->selectcol_arrayref(
            "SELECT transid FROM vgift_trans"
                . " WHERE rcptid=? AND delivered='Y' ORDER BY delivery_t DESC, "
                . " transid DESC",
            undef, $u->id
        ) || [];
        die $u->errstr if $u->err;
        LJ::MemCache::set( $memkey, $data );
    }

    # transform transaction IDs to objects
    my @loaded = grep { defined } map { $class->load( user => $u, id => $_ ) } @$data;

    # do any further filtering of results in caller
    return @loaded unless $opts{profile};

    # special case: profile only shows accepted & non-expired
    return grep { $_->is_accepted && !$_->is_expired } @loaded;
}

sub load {
    my ( $class, %opts ) = @_;

    # opts: user => (u or userid) - mandatory
    #       id => (transaction id) - mandatory

    return unless defined $opts{id};
    my $id = $opts{id} + 0;
    my $u  = LJ::want_user( $opts{user} ) or return;

    my $memkey = $class->_transaction_load_memkey( $u, $id );
    my $data   = LJ::MemCache::get($memkey);

    unless ( defined $data ) {
        $data = $u->selectrow_hashref(
            'SELECT transid, rcptid, vgiftid,'
                . ' buyerid, cartid, delivery_t, accepted, delivered, expired'
                . ' FROM vgift_trans WHERE rcptid=? AND transid=?',
            undef, $u->id, $id
        ) || {};
        die $u->errstr if $u->err;

        if ( my $item = $class->_search_cart($data) ) {
            $data->{reason} = $item->reason;
            $data->{anon}   = $item->anonymous;

            # from_html takes care of the anon/email/username display
            # if the item is found.  otherwise fall back to using buyerid.
            $data->{from} =
                $item->from_html ne LJ::Lang::ml('error.nojournal') ? $item->from_html : undef;
            $data->{from_text} =
                $item->from_text ne LJ::Lang::ml('error.nojournal') ? $item->from_text : undef;
        }

        LJ::MemCache::set( $memkey, $data );
    }

    return {} unless %$data;

    # populate some extra hash keys for convenience
    $data->{id}        = $data->{transid};
    $data->{user}      = LJ::want_user( $data->{rcptid} );
    $data->{vgift}     = DW::VirtualGift->new( $data->{vgiftid} );
    $data->{buyer}     = LJ::want_user( $data->{buyerid} );
    $data->{timestamp} = LJ::mysql_time( $data->{delivery_t} );

    return $class->new($data);
}

sub _search_cart {
    my ( $class, $data ) = @_;
    my $cart = DW::Shop::Cart->get_from_cartid( $data->{cartid} )
        or return;

    foreach my $item ( @{ $cart->items } ) {
        next unless ref $item eq 'DW::Shop::Item::VirtualGift';
        next unless $data->{rcptid} == $item->t_userid;
        next unless $data->{transid} == $item->vgift_transid;

        # if we get here, it's the right item
        return $item;
    }

    # we didn't find it - sadness
    return undef;
}

sub _transaction_load_memkey {
    my ( $class, $u, $id ) = @_;
    my $uid = $u->id or return;
    return [ $uid, "vgift.trans.$id" ];    # caches database row
}

sub _transaction_list_memkey {
    my ( $class, $u ) = @_;
    my $uid = $u->id or return;
    return [ $uid, "vgift.translist.$uid" ];    # caches list of transids
}

sub new {
    my ( $class, $self ) = @_;
    $class = ref $class if ref $class;
    return $self if ref $self eq $class;        # already blessed

    my ( $id, $uid ) = ( $self->{transid}, $self->{rcptid} );
    return unless ( $id && $id =~ /^\d+$/ ) && ( $uid && $uid =~ /^\d+$/ );

    bless $self, $class;
    return $self;
}

### OBJECT METHODS ###

sub id { $_[0]->{id} }
sub u  { $_[0]->{user} }

sub is_delivered { $_[0]->{delivered} eq 'Y' }
sub is_accepted  { $_[0]->{accepted} eq 'Y' }
sub is_expired   { $_[0]->{expired} eq 'Y' }

sub is_anonymous { $_[0]->{anon} ? 1 : 0 }

sub from_html {
    my ($self) = @_;
    return $self->{from} if defined $self->{from};
    return $self->{buyer}->ljuser_display if LJ::isu( $self->{buyer} );

    # undefined if neither of these is valid
}

sub from_text {
    my ($self) = @_;
    return $self->{from_text} if defined $self->{from_text};
    return $self->{buyer}->display_name if LJ::isu( $self->{buyer} );

    # undefined if neither of these is valid
}

sub _update {
    my ( $self, $sql, $expire ) = @_;
    my ( $id, $u ) = ( $self->id, $self->u );
    return unless $id  && LJ::isu($u);
    return unless $sql && $sql !~ /\?/;

    $u->do( "$sql WHERE rcptid=? AND transid=?", undef, $u->id, $id );
    die $u->errstr if $u->err;

    # memcache expiration for this one transaction
    LJ::MemCache::delete( $self->_transaction_load_memkey( $u, $id ) );

    # memcache expiration for list of all transactions
    # only needed for deliveries and deletions
    LJ::MemCache::delete( $self->_transaction_list_memkey($u) )
        if $expire;

    return 1;
}

sub remove {
    my ($self) = @_;
    return $self->_update( 'DELETE FROM vgift_trans', 1 );
}

sub accept {
    my ($self) = @_;
    return 1 if $self->is_accepted;    # already accepted
    $self->{accepted} = 'Y';           # update object in memory
    return $self->_update('UPDATE vgift_trans SET accepted="Y"');
}

sub deliver {
    my ($self) = @_;
    return 1 if $self->is_delivered;    # already delivered
    $self->{delivered} = 'Y';           # update object in memory
    return $self->_update( 'UPDATE vgift_trans SET delivered="Y", ' . 'delivery_t=UNIX_TIMESTAMP()',
        1 );
}

sub notify_delivered {
    my ($self) = @_;

    # make sure the gift was actually delivered
    return unless $self->is_delivered;

    # notify the user (no opt-out)
    my @args = ( $self->u, $self->id );
    LJ::Event::VgiftDelivered->new(@args)->fire;
}

sub url {
    my ($self) = @_;
    return unless LJ::isu( $self->u );
    return $self->u->journal_base . "/vgifts/" . $self->id;
}

sub view {

    # print mini view for profile page; standalone page should be TT
    # (expects virtualgift class in htdocs/stc/profile.css)

    my ($self) = @_;
    my $vg = $self->{vgift};
    return '' unless $vg && $vg->id;

    my $disp = $vg->img_small_html;

    # substitute the gift name if no image is set
    $disp = $vg->name_ehtml unless $disp =~ /^<img/i;

    my $url = $self->url;
    $disp = "<a href='$url'>$disp</a>" if $url;

    my $ret = "<div class='virtualgift'>$disp<br />";

    my $from_word = LJ::Lang::ml('widget.shopcart.header.from');
    my $anon_word = LJ::Lang::ml('widget.shopcart.anonymous');

    if ( $self->{anon} ) {
        $ret .= $from_word . " " . $anon_word;
    }
    elsif ( $self->{from} ) {

        # show the cached result of the cart item's from_html method
        $ret .= $from_word . " " . $self->{from};
    }
    elsif ( LJ::isu( $self->{buyer} ) ) {
        $ret .= $from_word . " " . $self->{buyer}->ljuser_display;
    }
    else {
        # if we can't show a user name, just print anonymous
        $ret .= $from_word . " " . $anon_word;
    }

    $ret .= "</div>\n";

    return $ret;
}

1;
