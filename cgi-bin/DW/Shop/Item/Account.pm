#!/usr/bin/perl
#
# DW::Shop::Item::Account
#
# Represents a paid account that someone is purchasing.
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

package DW::Shop::Item::Account;

use strict;


# instantiates an account to be purchased of some sort
sub new {
    my ( $class, %args ) = @_;

    my $type = delete $args{type};
    return undef unless exists $LJ::SHOP{$type};

    # at this point, there needs to be only one argument, and it needs to be one
    # of the target types
    return undef unless
        scalar( keys %args ) == 1 &&
            ( $args{target_username} || $args{target_userid} || $args{target_email} );

    # now do validation.  since new is only called when the item is being added
    # to the shopping cart, then we are comfortable doing all of these checks
    # on things at the time this item is put together
    if ( my $un = $args{target_username} ) {
        # username needs to be valid and not exist
        return undef unless $un = LJ::canonical_username( $un );
        return undef if LJ::load_user( $un );

        $args{target_username} = $un;

    } elsif ( my $uid = $args{target_userid} ) {
        # userid needs to exist
        return undef unless LJ::load_userid( $uid );

    } elsif ( my $email = $args{target_email} ) {
        # FIXME: validate email address

    }

    # looks good
    return bless {
        # user supplied arguments (close enough)
        cost    => $LJ::SHOP{$type}->[0] + 0.00,
        months  => $LJ::SHOP{$type}->[1],
        class   => $LJ::SHOP{$type}->[2],
        %args,

        # internal things we use to track the state of this item
        type    => 'account',
        applied => 0,
    }, $class;
}


# called when we are told we need to apply this item, i.e., turn it on.  note that we
# update ourselves, but it's up to the cart to make sure that it saves.
sub apply {
    my $self = $_[0];
    return if $self->applied;

    # do the application process now, and if it succeeds...
    $self->{applied} = 1;
    warn "$self->{class} applied $self->{months} months\n";

    return 1;
}


# called when we need to turn this item off
sub unapply {
    my $self = $_[0];
    return unless $self->applied;

    # do the application process now, and if it succeeds...
    $self->{applied} = 0;
    warn "$self->{class} unapplied $self->{months} months\n";

    return 1;
}


# given another item, see if that item conflicts with this item (i.e.,
# if you can't have both in your shopping cart at the same time).
#
# returns undef on "no conflict" else an error message.
sub conflicts {
    my ( $self, $item ) = @_;

    # first see if we're talking about the same target
    # FIXME: maybe not include email here, what happens if they want to buy 3 paid accounts
    # and send them to the same email address?
    return if
        ( $self->t_userid   && $self->t_userid   != $item->t_userid   ) ||
        ( $self->t_email    && $self->t_email    != $item->t_email    ) ||
        ( $self->t_username && $self->t_username != $item->t_username );

    # target same, if either is permanent, then fail because
    # THERE CAN BE ONLY ONE
    return 'Already purchasing a permanent account for this target.'
        if $self->permanent || $item->permanent;

    # otherwise ensure that the classes are the same
    return 'Already chose to upgrade to a ' . $self->class . ', do not do both!'
        if $self->class ne $item->class;

    # guess we allow it
    return undef;
}


# render our target as a string
sub t_html {
    my $self = $_[0];

    if ( my $uid = $self->t_userid ) {
        my $u = LJ::load_userid( $uid );
        return $u->ljuser_display
            if $u;
        return "<strong>invalid userid $uid</strong>";

    } elsif ( my $user = $self->t_username ) {
        my $u = LJ::load_user( $user );
        return $u->ljuser_display
            if $u;
        return "<strong>$user</strong>";

    } elsif ( my $email = $self->t_email ) {
        return "<strong>$email</strong>";

    }

    return "<strong>invalid/unknown target</strong>";
}


# this is a getter/setter so it is pulled out
sub id {
    return $_[0]->{id} unless defined $_[1];
    return $_[0]->{id} = $_[1];
}


# simple accessors
sub applied    { return $_[0]->{applied};         }
sub cost       { return $_[0]->{cost};            }
sub months     { return $_[0]->{months};          }
sub class      { return $_[0]->{class};           }
sub t_userid   { return $_[0]->{target_userid};   }
sub t_email    { return $_[0]->{target_email};    }
sub t_username { return $_[0]->{target_username}; }
sub permanent  { return $_[0]->months == 99;      }


1;
