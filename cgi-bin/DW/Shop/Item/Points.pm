#!/usr/bin/perl
#
# DW::Shop::Item::Points
#
# Represents Dreamwidth Points that someone is buying.
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

package DW::Shop::Item::Points;

use base 'DW::Shop::Item';

use strict;
use DW::InviteCodes;
use DW::Pay;

=head1 NAME

DW::Shop::Item::Points - Represents a block of points that someone is purchasing. See
the documentation for DW::Shop::Item for usage examples and description of methods
inherited from that base class.

=head1 API

=head2 C<< $class->new( [ %args ] ) >>

Instantiates a block of points to be purchased.

Arguments:
=item ( see DW::Shop::Item ),
=item points => number of points to buy,

=cut

# override
sub new {
    my ( $class, %args ) = @_;

    my $self = $class->SUPER::new( %args, type => 'points' );
    return unless $self;

    if ( $args{transfer} ) {
        $self->{cost_cash} = 0;
        $self->{cost_points} = $self->{points};
    } else {
        $self->{cost_cash} = $self->{points} / 10;
        $self->{cost_points} = 0;
    }

    # for now, we can only apply to a user.  in the future this is an obvious way
    # to do gift certificates by allowing an email address here...
    die "Can only give points to an account.\n"
        unless $self->t_userid;

    return $self;
}


# override
sub _apply {
    my $self = $_[0];

    return $self->_apply_userid if $self->t_userid;

    # something weird, just kill this item!
    $self->{applied} = 1;
    return 1;
}


# internal application sub, do not call
sub _apply_userid {
    my $self = $_[0];
    return 1 if $self->applied;

    # will need this later
    my $fu = LJ::load_userid( $self->from_userid );
    unless ( $fu ) {
        warn "Failed to apply: invalid from_userid!\n";
        return 0;
    }

    # need this user
    my $u = LJ::load_userid( $self->t_userid )
        or return 0;

    # now try to add the points
    $u->give_shop_points( amount => $self->points, reason => 'ordered; item #' . $self->id );

    DW::Stats::increment( 'dw.shop.points.applied', $self->points,
            [ 'gift:' . ( $fu->equals( $u ) ? 'no' : 'yes' ) ] );

    # we're applied now, regardless of what happens with the email
    $self->{applied} = 1;

    # now we have to mail this code
    my $word = $fu->equals( $u ) ? 'self' : 'other';
    my $body = LJ::Lang::ml( "shop.email.gift.$word.body",
        {
            touser => $u->display_name,
            fromuser => $fu->display_name,
            sitename => $LJ::SITENAME,
            gift => sprintf( '%d %s Points', $self->points, $LJ::SITENAMESHORT ),
        }
    );
    my $subj = LJ::Lang::ml( "shop.email.gift.$word.subject", { sitename => $LJ::SITENAME } );

    # send the email to the user
    LJ::send_mail( {
        to       => $u->email_raw,
        from     => $LJ::ACCOUNTS_EMAIL,
        fromname => $LJ::SITENAME,
        subject  => $subj,
        body     => $body
    } );

    # tell the caller we're happy
    return 1;
}


# override
sub unapply {
    my $self = $_[0];
    return unless $self->applied;

    # unapplying is not coded yet, as we don't have good automatic support for orders being
    # reverted and refunded.
    $self->{applied} = 0;
    die "Unable to unapply right now.\n";

    return 1;
}


# override
sub can_be_added {
    my ( $self, %opts ) = @_;

    return 0 unless $self->can_be_added_user( %opts );
    return 0 unless $self->can_be_added_points( %opts );

    return 1;
}

sub can_be_added_user {
    my ( $self, %opts ) = @_;

    my $errref = $opts{errref};

    # if not a valid account, error
    my $target_u = LJ::load_userid( $self->t_userid );
    if ( ! LJ::isu( $target_u ) ) {
        $$errref = LJ::Lang::ml( 'shop.item.points.canbeadded.notauser' );
        return 0;
    }

    # the receiving user must be a person for now
    unless ( $target_u->is_personal && $target_u->is_visible ) {
        $$errref = LJ::Lang::ml( 'shop.item.points.canbeadded.invalidjournaltype' );
        return 0;
    }

    # make sure no sysban is in effect here
    my $fromu = LJ::load_userid( $self->from_userid );
    if ( $fromu && $target_u->has_banned( $fromu ) ) {
        $$errref = LJ::Lang::ml( 'shop.item.points.canbeadded.banned' );
        return 0;
    }

    return 1;
}

sub can_be_added_points {
    my ( $self, %opts ) = @_;

    my $errref = $opts{errref};

    # sanity check that the points are positive and not more than 5000
    unless ( $self->points > 0 && $self->points <= 5000 ) {
        $$errref = LJ::Lang::ml( 'shop.item.points.canbeadded.outofrange' );
        return 0;
    }

    # sanity check that the points are above the purchase minimum, but only
    # if they're being purchased.  we allow small point transfers at no cost.
    if ( $self->cost_cash > 0.00 && $self->points < 30 ) {
        $$errref = LJ::Lang::ml( 'shop.item.points.canbeadded.outofrange' );
        return 0;
    }

    return 1;
}


# override
sub name_text {
    my $self = $_[0];

    return LJ::Lang::ml( 'shop.item.points.name', { num => $self->points, sitename => $LJ::SITENAMESHORT } );
}


=head2 C<< $self->points >>

Return how many points this item is worth.

=cut

sub points { $_[0]->{points} }


1;
