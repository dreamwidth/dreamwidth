#!/usr/bin/perl
#
# DW::Shop::Item::Icons
#
# Represents Dreamwidth Icons that someone is buying.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Shop::Item::Icons;

use base 'DW::Shop::Item';

use strict;
use DW::InviteCodes;
use DW::Pay;

=head1 NAME

DW::Shop::Item::Icons - Represents extra icons that someone is purchasing. See
the documentation for DW::Shop::Item for usage examples and description of methods
inherited from that base class.

=head1 API

=head2 C<< $class->new( [ %args ] ) >>

Instantiates a block of icons to be purchased.

Arguments:
=item ( see DW::Shop::Item ),
=item icons => number of icons to buy,

=cut

# override
sub new {
    my ( $class, %args ) = @_;

    my $self = $class->SUPER::new( %args, type => 'icons' );
    return unless $self;

    # Set up our initial cost structure
    $self->{cost_cash}   = $self->{icons};
    $self->{cost_points} = $self->{icons} * 10;

    # for now, we can only apply to a user.  in the future this is an obvious way
    # to do gift certificates by allowing an email address here...
    die "Can only give icons to an account.\n"
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
    unless ($fu) {
        warn "Failed to apply: invalid from_userid!\n";
        return 0;
    }

    # need this user
    my $u = LJ::load_userid( $self->t_userid )
        or return 0;

    # validate that they can get this number of icons
    my $cur = $u->prop('bonus_icons') // 0;
    $u->set_prop( bonus_icons => $cur + $self->icons );
    LJ::statushistory_add( $u, $fu, 'bonus_icons',
        sprintf( '%d icons added; item #%d', $self->icons, $self->id ) );

    DW::Stats::increment( 'dw.shop.icons.applied', $self->icons,
        [ 'gift:' . ( $fu->equals($u) ? 'no' : 'yes' ) ] );

    # we're applied now, regardless of what happens with the email
    $self->{applied} = 1;

    # see if this has put the user over their limit
    my $overlimit  = '';
    my $real_total = $self->icons + $u->get_cap('userpics') + $cur;
    if ( $real_total > $LJ::USERPIC_MAXIMUM ) {
        $overlimit = LJ::Lang::ml(
            'shop.item.icons.overlimit',
            {
                sitename => $LJ::SITENAMESHORT,
                max      => $LJ::USERPIC_MAXIMUM,
                overage  => $real_total - $LJ::USERPIC_MAXIMUM
            }
        );
    }

    # now we have to mail this notification
    my $word = $fu->equals($u) ? 'self' : 'other';
    my $body = LJ::Lang::ml(
        "shop.email.gift.$word.body",
        {
            touser   => $u->display_name,
            fromuser => $fu->display_name,
            sitename => $LJ::SITENAME,
            gift     => sprintf( '%d %s Extra Icons', $self->icons, $LJ::SITENAMESHORT ),
            extra    => $overlimit,
        }
    );
    my $subj = LJ::Lang::ml( "shop.email.gift.$word.subject", { sitename => $LJ::SITENAME } );

    # send the email to the user
    LJ::send_mail(
        {
            to       => $u->email_raw,
            from     => $LJ::ACCOUNTS_EMAIL,
            fromname => $LJ::SITENAME,
            subject  => $subj,
            body     => $body
        }
    );

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

    return 0 unless $self->can_be_added_user(%opts);
    return 0 unless $self->can_be_added_icons(%opts);

    return 1;
}

sub can_be_added_user {
    my ( $self, %opts ) = @_;
    my $errref = $opts{errref};

    # if not a valid account, error
    my $target_u = LJ::load_userid( $self->t_userid );
    if ( !LJ::isu($target_u) ) {
        $$errref = LJ::Lang::ml('shop.item.icons.canbeadded.notauser');
        return 0;
    }

    # the receiving user must be a person for now
    unless ( $target_u->is_personal && $target_u->is_visible ) {
        $$errref = LJ::Lang::ml('shop.item.icons.canbeadded.invalidjournaltype');
        return 0;
    }

    # and they must be paid
    unless ( $target_u->can_buy_icons ) {
        $$errref = LJ::Lang::ml('shop.item.icons.canbeadded.notpaid');
        return 0;
    }

    # make sure no sysban is in effect here
    my $fromu = LJ::load_userid( $self->from_userid );
    if ( $fromu && $target_u->has_banned($fromu) ) {
        $$errref = LJ::Lang::ml('shop.item.icons.canbeadded.banned');
        return 0;
    }

    return 1;
}

sub can_be_added_icons {
    my ( $self, %opts ) = @_;
    my $errref = $opts{errref};

    # sanity check that the icons to add are within range
    my $target_u  = LJ::load_userid( $self->t_userid );
    my $pics_left = $LJ::USERPIC_MAXIMUM - $target_u->userpic_quota;
    unless ( $self->icons > 0 && $self->icons <= $pics_left ) {
        $$errref = LJ::Lang::ml( 'shop.item.icons.canbeadded.outofrange', { count => $pics_left } );
        return 0;
    }

    return 1;
}

# override
sub name_text {
    my $self = $_[0];

    return LJ::Lang::ml( 'shop.item.icons.name',
        { num => $self->icons, sitename => $LJ::SITENAMESHORT } );
}

=head2 C<< $self->icons >>

Return how many icons this item is worth.

=cut

sub icons { $_[0]->{icons} }

1;
