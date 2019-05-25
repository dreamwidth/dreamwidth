#!/usr/bin/perl
#
# DW::Shop::Item::VirtualGift
#
# Represents a virtual gift that someone is purchasing.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2012-2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Shop::Item::VirtualGift;

use base 'DW::Shop::Item';
use strict;

use DW::VirtualGiftTransaction;
use DW::VirtualGift;

=head1 NAME

DW::Shop::Item::VirtualGift - Represents a virtual gift that someone is
purchasing. See the documentation for DW::Shop::Item for usage examples and
description of methods inherited from that base class.

=head1 API

=cut

=head2 C<< $class->new( [ %args ] ) >>

Instantiates a virtual gift to be purchased.

Arguments:
=item ( see DW::Shop::Item ),
=item vgiftid => id of virtual gift being purchased,

=cut

sub new {
    my ( $class, %args ) = @_;

    # must have been sent to a user
    return undef unless $args{target_userid};

    # must refer to an active virtual gift in the database
    my $vg = DW::VirtualGift->new( $args{vgiftid} );
    return undef unless $vg && $vg->is_active;

    my $self = $class->SUPER::new( %args, type => "vgifts" );
    return undef unless $self;

    # look up costs from database
    $self->{cost_points} = $vg->cost;
    $self->{cost_cash}   = $vg->cost / 10;

    return $self;
}

sub conflicts {
    my ( $self, $item ) = @_;

    # check parent method first
    my $rv = $self->SUPER::conflicts($item);
    return $rv if $rv;

    # subclasses can add additional logic here

    # guess we allow it
    return undef;
}

# override
sub name_text {
    my $vg = $_[0]->vgift
        or return LJ::Lang::ml('shop.item.vgift.name.notfound');
    return $vg->name;

# FIXME: syntax below looks to come from short_desc instead;
# need to hook into shop before determining how to best display these
#     return ( my $u = LJ::load_userid( $_[0]->t_userid ) )
#         ? LJ::Lang::ml( 'shop.item.vgift.name.foruser.text', { name => $vg->name, user => $u->display_name } )
#         : LJ::Lang::ml( 'shop.item.vgift.name.text', { name => $vg->name } );
}

# override
sub name_html {
    my $vg = $_[0]->vgift
        or return LJ::Lang::ml('shop.item.vgift.name.notfound');
    return $vg->name_ehtml;

#     return ( my $u = LJ::load_userid( $_[0]->t_userid ) )
#         ? LJ::Lang::ml( 'shop.item.vgift.name.foruser.html', { name => $vg->name_ehtml, user => $u->ljuser_display } )
#         : LJ::Lang::ml( 'shop.item.vgift.name.html', { name => $vg->name_ehtml } );
}

# override
sub note {

    # show the mini image
    my $vg = $_[0]->vgift or return '';
    return $vg->img_small_html;
}

# we do want the paidstatus worker to deliver these for us.
sub apply_automatically { 1 }

# override
sub _apply {
    my ( $self, %opts ) = @_;
    my %args = ( user => $self->t_userid, id => $self->vgift_transid );

    my $trans = DW::VirtualGiftTransaction->load(%args)
        or return 0;

    # abort if already delivered
    return $self->{applied} = 1 if $trans->is_delivered;

    # attempt the delivery - parent method already made sure
    #  that the delivery date isn't in the future
    return 0 unless $trans->deliver;

    # notify the user about this gift
    $trans->notify_delivered unless $LJ::T_SUPPRESS_EMAIL;

    return $self->{applied} = 1;
}

# override
sub can_be_added {
    my ( $self, %opts ) = @_;

    my $errref   = $opts{errref};
    my $target_u = LJ::load_userid( $self->t_userid );
    my $from_u   = LJ::load_userid( $self->from_userid );
    my $anon     = $self->anonymous;

    # check the preferences of the receiving user
    return 1 if LJ::isu($target_u) && $target_u->can_receive_vgifts_from( $from_u, $anon );

    # not allowed; error message depends on anonymity
    $$errref =
        $anon
        ? LJ::Lang::ml('shop.item.vgift.canbeadded.noanon')
        : LJ::Lang::ml('shop.item.vgift.canbeadded.refused');
    return 0;
}

# override
sub cart_state_changed {
    my ( $self, $newstate ) = @_;
    return unless $newstate == $DW::Shop::STATE_PAID && !$self->vgift_transid;

    # cart has just been paid for, so we need to create a new transaction row

    my $u = LJ::load_userid( $self->t_userid ) or return 0;

    my %opts = (
        user   => $u,
        vgift  => $self->vgift,
        buyer  => $self->from_userid,
        cartid => $self->cartid
    );

    my $transid = DW::VirtualGiftTransaction->save(%opts);
    return undef unless $transid;

    return $self->{vgift_transid} = $transid;
}

=head2 C<< $self->vgift >>

Returns the virtual gift object.

=head2 C<< $self->vgift_transid >>

Returns the transaction ID associated with this purchase.

=cut

sub vgift { DW::VirtualGift->new( $_[0]->{vgiftid} ) }

sub vgift_transid { $_[0]->{vgift_transid} }

1;
