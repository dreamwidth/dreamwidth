#!/usr/bin/perl
#
# DW::Media::Base
#
# This is the base module to represent media items.  You should never instantiate
# this class directly...
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

package DW::Media::Base;

use strict;
use Carp qw/ croak confess /;

sub new_from_row {
    my ( $class, %opts ) = @_;

    # if the class is base, intuit something...
    confess 'Please do not build the base class.'
        if $class eq 'DW::Media::Base';

    # simply bless and return then, we don't do anything smart here yet
    return bless \%opts, $class;
}

# accessors for our internal data
sub u { LJ::load_userid( $_[0]->{userid} ) }
sub userid { $_[0]->{userid} }
sub id { $_[0]->{mediaid} }
sub anum { $_[0]->{anum} }
sub displayid { $_[0]->{mediaid} * 256 + $_[0]->{anum} }
sub state { $_[0]->{state} }
sub mediatype { $_[0]->{mediatype} }
sub security { $_[0]->{security} }
sub allowmask { $_[0]->{allowmask} }
sub logtime { $_[0]->{logtime} }
sub mimetype { $_[0]->{mimetype} }
sub size { $_[0]->{filesize} }
sub mogkey { "media:$_[0]->{userid}:$_[0]->{mediaid}" }
sub ext { $_[0]->{ext} }

# helper state subs
sub is_active { $_[0]->state eq 'A' }
sub is_deleted { $_[0]->state eq 'D' }

# construct a URL for this resource
sub url {
    my ( $self, $extra ) = ( $_[0], '' );
    if ( $_[1] && ref $_[1] eq 'HASH' ) {
        # If either width or height is specified, add the extra output
        my ( $w, $h ) = ( $_[1]->{width}||'', $_[1]->{height}||'' );
        $extra = $w . 'x' . $h . '/'
            if $w || $h;
    }
    return $self->u->journal_base . '/file/' . $extra . $self->displayid . '.' . $self->ext;
}

# if user can see this
sub visible_to {
    my ( $self, $other_u ) = @_;

    # test that the user that owns this item is still visible, that we're still active,
    # and return a true if we're public.
    my $u = $self->u;
    return 0 unless $self->is_active && $u->is_visible;
    return 1 if $self->security eq 'public';

    # at this point, if we don't have a remote user, fail
    return 0 unless LJ::isu( $other_u );

    # private check.  if it's us, allow, else fail.
    return 1 if $u->equals( $other_u );
    return 0 if $self->security eq 'private';

    # simple usemask checking...
    if ( $self->security eq 'usemask' ) {
        my $gmask = $u->trustmask( $other_u );

        my $allowed = int $gmask & int $self->allowmask;
        return $allowed ? 1 : 0;
    }

    # totally failed.
    return 0;
}

# we delete the actual file
# but we keep the metadata around for record-keeping purpose
# returns 1/0 on success or failure
sub delete {
    my $self = $_[0];
    return 0 if $self->is_deleted;

    # we need a mogilefs client or we can't edit media
    my $mog = LJ::mogclient()
        or croak 'Sorry, MogileFS is not currently available.';
    my $u = $self->u
        or croak 'Sorry, unable to load the user.';

    $u->do( q{UPDATE media SET state = 'D' WHERE userid = ? AND mediaid = ?},
            undef, $u->id, $self->id );
    confess $u->errstr if $u->err;

    $self->{state} = 'D';

    LJ::mogclient()->delete( $self->mogkey );

    return 1;
}

# change the security of this item. returns 0/1 for successfulness.
sub set_security {
    my ( $self, %opts ) = @_;
    return 0 if $self->is_deleted;

    my $security = $opts{security};
    confess 'Invalid security type passed to set_security.'
        unless $security =~ /^(?:private|public|usemask)$/;

    my $mask = 0;
    if ( $security eq 'usemask' ) {
        $mask = int $opts{allowmask};
    }

    my $u = $self->u
        or croak 'Sorry, unable to load the user.';
    $u->do( q{UPDATE media SET security = ?, allowmask = ? WHERE userid = ? AND mediaid = ?},
            undef, $security, $mask, $u->id, $self->id );
    confess $u->errstr if $u->err;

    $self->{security} = $security;
    $self->{allowmask} = $mask;

    return 1;
}


1;
