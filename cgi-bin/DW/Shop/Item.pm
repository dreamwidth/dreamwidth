#!/usr/bin/perl
#
# DW::Shop::Item
#
# Base class containing basic behavior for items to be sold in the shop
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Janine Smith <janine@netrophic.com>
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Shop::Item;

use strict;
use Carp;
use DW::InviteCodes;
use DW::Pay;

=head1 NAME

DW::Shop::Item - base class containing basic behavior for items to be sold in the shop

=head1 SYNOPSIS

=head1 API

=head2 C<< $class->new(  [ $opts ] ) >>

Instantiates an item to be purchased in the shop. The item must be defined in the
%LJ::SHOP hash in your config file.

Arguments:
=item type => item type, passed in by a subclass. Must be configured in %LJ::SHOP
=item target_userid => userid,
=item target_email => email,
=item from_userid => userid,
=item deliverydate => "yyyy-mm-dd",
=item anonymous => 1,
=item anonymous_target => 1,
=item cannot_conflict => 1,
=item noremove => 1,
=item from_name => sender name,
=item reason => personal note from sender to target

The type is required. Also, one target_* argument is required; it may be either
a target_userid or a target_email. All other arguments are optional.

Subclasses must override this function to set the type. Subclasses may also do any
other modifications necessary when instantiating itself. See DW::Shop::Item::Account
for an example.

=cut

sub new {
    my ( $class, %args ) = @_;
    return undef unless exists $LJ::SHOP{ $args{type} };

    # from_userid will be 0 or undef if the sender isn't logged in
    # but if we have a userid, and it doesn't load properly, bail out here.
    return undef if $args{from_userid} && !LJ::load_userid( $args{from_userid} );

    # now do validation.  since new is only called when the item is being added
    # to the shopping cart, then we are comfortable doing all of these checks
    # on things at the time this item is put together
    if ( my $uid = $args{target_userid} ) {

        # userid needs to exist
        return undef unless LJ::load_userid($uid);
    }
    elsif ( my $email = $args{target_email} ) {

        # email address must be valid
        my @email_errors;
        LJ::check_email( $email, \@email_errors,
            { force_spelling => delete $args{force_spelling} } );
        return undef if @email_errors;
    }
    else {
        return undef;
    }

    if ( $args{deliverydate} ) {
        return undef unless $args{deliverydate} =~ /^\d\d\d\d-\d\d-\d\d$/;
    }

    if ( $args{anonymous} ) {
        return undef unless $args{anonymous} == 1;
    }

    if ( $args{cannot_conflict} ) {
        return undef unless $args{cannot_conflict} == 1;
    }

    if ( $args{noremove} ) {
        return undef unless $args{noremove} == 1;
    }

    # looks good
    my $confargs = $LJ::SHOP{ $args{type} };    # arrayref

    # points and vgifts have empty args, which will cause undef warnings
    $confargs = [ 0, 0, 0, 0 ] unless scalar @$confargs;

    return bless {

        # user supplied arguments (close enough)
        cost_cash   => $confargs->[0] + 0.00,
        cost_points => $confargs->[3] + 0,
        %args,

        # internal things we use to track the state of this item,
        applied => 0,
        cartid  => 0,
    }, $class;
}

=head2 C<< $self->apply_automatically >>

True if you want the item to be applied via the paidstatus worker, and false
if you wish to apply the item yourself (usually triggered by a user action).

Subclasses may override.

=cut

sub apply_automatically { 1 }

=head2 C<< $self->apply >>

Called when we are told we need to apply this item, i.e., turn it on. Note that we
update ourselves, but it's up to the cart to make sure that it saves.

Subclasses may override this method, but a better approach would be to override the
internal $self->_apply method.

=cut

sub apply {
    my $self = shift;
    return 1 if $self->applied;

    # 1) deliverydate must be present/past
    if ( my $ddate = $self->deliverydate ) {
        my $cur = LJ::mysql_time();
        $cur =~ s/^(\d\d\d\d-\d\d-\d\d).+$/$1/;

        return 0
            unless $ddate le $cur;
    }

    return $self->_apply(@_);
}

=head2 C<< $self->_apply >>

Internal application sub.

Subclasses must override this for item-specific behavior.

=cut

sub _apply {
    croak "Cannot apply shop item; this method must be override by a subclass.";
}

=head2 C<< $self->unapply >>

Called when we need to turn this item off.

Subclasses may override this to add additional behavior or warnings.

=cut

sub unapply {
    my $self = $_[0];
    return unless $self->applied;

    # do the application process now, and if it succeeds...
    $self->{applied} = 0;

    return 1;
}

=head2 C<< $self->cart_state_changed( $cart, $newstate ) >>

Hook in the cart for custom behavior once the cart has been changed.

Subclasses may override this for custom behavior: for example, creating a token or certificate once the cart has been paid for.

=cut

sub cart_state_changed {
    my ( $cart, $newstate ) = @_;
}

=head2 C<< $self->can_be_added( [ %opts ] ) >>

Returns 1 if this item is allowed to be added to the shopping cart.

Subclasses must override this.

=cut

sub can_be_added {
    my ( $self, %opts ) = @_;

    return 1;
}

=head2 C<< $self->can_have_reason( [ %opts ] ) >>

Returns 1 if this item is allowed to have a personal note from the
sender explaining the reason for the gift.

Subclasses must override this in order to disallow.

=cut

sub can_have_reason {
    my ( $self, %opts ) = @_;

    return 1;
}

=head2 C<< $self->conflicts( $item ) >>

Given another item, see if that item conflicts with this item (i.e.,
if you can't have both in your shopping cart at the same time).

Returns undef on "no conflict" else an error message.

Subclasses may override.

=cut

sub conflicts {
    my ( $self, $item ) = @_;

    # if either item are set as "does not conflict" then never say yes
    return
        if $self->cannot_conflict || $item->cannot_conflict;

    # subclasses can add additional logic here

    # guess we allow it
    return undef;
}

=head2 C<< $self->t_html( [ %opts ] ) >>

Render our target as a string.

Subclasses may override.

=cut

sub t_html {
    my ( $self, %opts ) = @_;

    if ( my $uid = $self->t_userid ) {
        my $u = LJ::load_userid($uid);
        return $u->ljuser_display
            if $u;
        return "<strong>invalid userid $uid</strong>";

    }
    elsif ( my $email = $self->t_email ) {
        return "<strong>$email</strong>";

    }

    return "<strong>invalid/unknown target</strong>";
}

=head2 C<< $self->name_text >>

Render the item name as a string, for display, to be used in contexts which don't allow HTML.

Subclasses must override to provide a more specific and user-friendly display name.

=cut

sub name_text {
    return ref $_[0];
}

=head2 C<< $self->name_html >>

Render the item name as a string for display, to be used in contexts which accept HTML.

Subclasses may override to provide a version of the name containing HTML. Uses $self->name_text by default.

=cut

sub name_html {
    return $_[0]->name_text;
}

=head2 C<< $self->note >>

Render a note to the user about this item.

Subclasses may override to provide a brief note about this item.

=cut

sub note {
    return "";
}

=head2 C<< $self->short_desc >>

Returns a short string talking about what this is.

Subclasses may override to provide further description.

=cut

sub short_desc {
    my ( $self, %opts ) = @_;

    # does not contain HTML, I hope
    my $desc = $opts{nohtml} ? $self->name_text : $self->name_html;

    my $for = $self->t_email;
    unless ($for) {
        my $u = LJ::load_userid( $self->t_userid );
        $for = $u->user
            if $u;
    }

    # FIXME: english strip
    return "$desc for $for";
}

=head2 C<< $self->id( $id ) >>

This is a getter/setter so it is pulled out.

=cut

sub id {
    return $_[0]->{id} unless defined $_[1];
    return $_[0]->{id} = $_[1];
}

=head2 C<< $self->cartid( $cartid ) >>

Gets/sets.

=cut

sub cartid {
    return $_[0]->{cartid} unless defined $_[1];
    return $_[0]->{cartid} = $_[1];
}

=head2 C<< $self->t_userid( $target_userid ) >>

Gets/sets.

=cut

sub t_userid {
    return $_[0]->{target_userid} unless defined $_[1];
    return $_[0]->{target_userid} = $_[1];
}

=head2 C<< $self->from_html >>

Display who this is from, using ljuser_display.

=head2 C<< $self->from_text >>

Display who this is from, using display_name.

=cut

sub from_html {
    my $self = $_[0];

    my $from = $self->_from_other;
    return LJ::isu($from) ? $from->ljuser_display : LJ::ehtml($from);
}

sub from_text {
    my $self = $_[0];

    my $from = $self->_from_other;
    return LJ::isu($from) ? $from->display_name : $from;
}

sub _from_other {
    my $self = $_[0];

    return LJ::Lang::ml('widget.shopcart.anonymous') if $self->anonymous;
    return $self->from_name if $self->from_name;

    my $from_u = LJ::load_userid( $self->from_userid );
    return LJ::Lang::ml('error.nojournal') unless LJ::isu($from_u);

    return $from_u;
}

=head2 C<< $self->paid_cash >>

Returns the amount paid for this item in USD.  This varies from cart to cart
and item to item and is a reflection of the actual amount of cash paid for
this item.  paid_points may also be non-zero.

=cut

# this method has to be aware of old items
sub paid_cash {
    my $self = $_[0];

    # we try to promote the item to a new style.  we don't know if this is
    # going to get saved in the cart or not ...
    if ( exists $self->{cost} ) {
        $self->{paid_cash}   = delete( $self->{cost} ) + 0.00;
        $self->{paid_points} = 0;
    }

    return $_[0]->{paid_cash} unless defined $_[1];
    return $_[0]->{paid_cash} = $_[1];
}

=head2 C<< $self->paid_points >>

Returns the amount paid in points for this item.  This varies just like the
paid_cash item, which may also be non-zero for items that a user paid both
cash and points for.

=cut

sub paid_points {
    return $_[0]->{paid_points} unless defined $_[1];
    return $_[0]->{paid_points} = $_[1];
}

=head2 C<< $self->display_paid >>

Displays how much cash and/or points this item costs right now.

=cut

sub display_paid {
    my $self = $_[0];
    if ( $self->paid_cash && $self->paid_points ) {
        return sprintf( '$%0.2f USD and %d points', $self->paid_cash, $self->paid_points );
    }
    elsif ( $self->paid_cash ) {
        return sprintf( '$%0.2f USD', $self->paid_cash );
    }
    elsif ( $self->paid_points ) {
        return sprintf( '%d points', $self->paid_points );
    }
    else {
        return 'free';
    }
}

=head2 C<< $self->display_paid_cash >>

Display how much cash this item costs right now.

=head2 C<< $self->display_paid_points >>

Display how many points this item costs right now.

=head2 C<< $self->applied >>

Returns whether the item which was bought has been already applied

=head2 C<< $self->cost_cash >>

Returns the cost in USD of the item, as configured for this site.

=head2 C<< $self->cost_points >>

Returns the cost in points of the item, as configured for this site.

=head2 C<< $self->t_email >>

Returns the target email this item was sent to.

=head2 C<< $self->from_userid >>

Returns the userid of the person who bought this item. May be 0.

=head2 C<< $self->deliverydate >>

Returns the date this item should be delivered, in "yyyy-mm-dd" format

=head2 C<< $self->anonymous >>

Returns whether this item should be gifted anonymously, or credited to the sender

=head2 C<< $self->noremove >>

Returns whether this item may or may not be removed from the cart. May be used by
promotions which automatically add a promo item to a user's cart, to prevent the
promo item from being removed

=head2 C<< $self->from_name >>

Name of the sender in special cases. For example, can be the site name for
promotions. Not exposed/settable via the shop.

=head2 C<< $self->reason >>

Optional note from the sender explaining the reason for the gift.

=cut

sub display_paid_cash   { sprintf( '$%0.2f USD', $_[0]->paid_cash ) }
sub display_paid_points { sprintf( '%d points',  $_[0]->paid_points ) }
sub applied             { return $_[0]->{applied}; }
sub cost_points         { return $_[0]->{cost_points}; }
sub t_email             { return $_[0]->{target_email}; }
sub from_userid         { return $_[0]->{from_userid}; }
sub deliverydate        { return $_[0]->{deliverydate}; }
sub anonymous           { return $_[0]->{anonymous}; }
sub noremove            { return $_[0]->{noremove}; }
sub from_name           { return $_[0]->{from_name}; }
sub reason              { return $_[0]->{reason}; }

# this has to work with old items (pre-points) too
sub cost_cash {
    my $self = $_[0];
    return $self->{cost} + 0.00 if exists $self->{cost};
    return $self->{cost_cash} + 0.00;
}

=head2 C<< $self->cannot_conflict >>

Returns whether this item may never conflict with any other item. If true, skip
checks for conflict.

Subclasses may override.

=cut

sub cannot_conflict { return $_[0]->{cannot_conflict}; }

1;
