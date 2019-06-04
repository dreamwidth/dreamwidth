#!/usr/bin/perl
#
# DW::Collection
#
# This represents a collection -- aka, a gallery of various items that you
# have collected together into a category.
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
# This module allows you to organize a group of things that exist on the site
# for viewing and group commenting. Think of it as a gallery organizer that
# lets you put together various things and do stuff. Yeah, isn't that vague?
#

package DW::Collection;

use strict;
use Carp qw/ croak confess /;

use DW::Collection::Item;

# Load a collection for a user, this is not how you create one
sub new {
    my ( $class, %opts ) = @_;
    confess 'Need a user and colid key'
        unless $opts{user} && LJ::isu( $opts{user} ) && $opts{colid};

    my $hr = $opts{user}->selectrow_hashref(
        q{SELECT userid, colid, anum, state, security, allowmask, logtime,
            paruserid, parcolid
          FROM collections WHERE userid = ? AND colid = ?},
        undef, $opts{user}->id, $opts{colid}
    );
    return if $opts{user}->err || !$hr;

    return bless $hr, $class;
}

# accessors for our internal data
sub u             { $_[0]->{_u} ||= LJ::load_userid( $_[0]->{userid} ) }
sub userid        { $_[0]->{userid} }
sub id            { $_[0]->{colid} }
sub parent_userid { $_[0]->{paruserid} }
sub parent_id     { $_[0]->{parcolid} }
sub anum          { $_[0]->{anum} }
sub displayid     { $_[0]->{colid} * 256 + $_[0]->{anum} }
sub state         { $_[0]->{state} }
sub security      { $_[0]->{security} }
sub allowmask     { $_[0]->{allowmask} }
sub logtime       { $_[0]->{logtime} }

# instantiate and load our parent collection
sub parent {
    my $self = $_[0];
    return undef unless $self->{paruserid};

    my $paru = LJ::load_userid( $self->{paruserid} );
    return DW::Collection->new( user => $paru, colid => $self->{parcolid} );
}

# helper state subs
sub is_active { $_[0]->state eq 'A' }

# load items for the collection
sub items {
    my $self = $_[0];
    return wantarray ? @{ $self->{_items} } : $self->{_items}
        if exists $self->{_items};

    my $u  = $self->u;
    my $hr = $u->selectall_hashref(
        q{SELECT userid, colitemid, colid, itemtype, itemownerid, itemid, logtime
          FROM collection_items WHERE userid = ? AND colid = ?},
        'colitemid', undef, $u->id, $self->id
    );
    croak $u->errstr if $u->err;
    return () unless $hr;

    my @res;
    foreach my $colitemid ( keys %$hr ) {
        my $item = $hr->{$colitemid};
        push @res, DW::Collection::Item->new_from_row(%$item);
    }
    $self->{_items} = \@res;

    return wantarray ? @res : \@res;
}

# if user can see this
# FIXME: move this out to a general function?
sub visible_to {
    my ( $self, $other_u ) = @_;
    return 0 unless $other_u;

    # test that the user that owns this item is still visible, that we're still active,
    # and return a true if we're public.
    my $u = $self->u;
    return 0 unless $self->is_active && $u->is_visible;
    return 1 if $self->security eq 'public';

    # at this point, if we don't have a remote user, fail
    return 0 unless LJ::isu($other_u);

    # private check.  if it's us, allow, else fail.
    return 1 if $u->equals($other_u);
    return 0 if $self->security eq 'private';

    # simple usemask checking...
    if ( $self->security eq 'usemask' ) {
        my $gmask = $u->trustmask($other_u);

        my $allowed = int $gmask & int $self->allowmask;
        return $allowed ? 1 : 0;
    }

    # totally failed.
    return 0;
}

1;
