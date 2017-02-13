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
# Copyright (c) 2010-2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Media::Base;

use strict;
use Carp qw/ croak confess /;

use DW::BlobStore;

sub new_from_row {
    croak "Children must override this method.";
}

# accessors for our internal data
sub u { LJ::load_userid( $_[0]->{userid} ) }
sub userid { $_[0]->{userid} }
sub id { $_[0]->{mediaid} }
sub anum { $_[0]->{anum} }
sub displayid { $_[0]->{displayid} }
sub state { $_[0]->{state} }
sub mediatype { $_[0]->{mediatype} }
sub security { $_[0]->{security} }
sub allowmask { $_[0]->{allowmask} }
sub logtime { $_[0]->{logtime} }
sub mimetype { $_[0]->{mimetype} }
sub mogkey { "media:$_[0]->{userid}:$_[0]->{versionid}" }
sub ext { $_[0]->{ext} }

# These change depending on the version we're showing.
sub versionid { $_[0]->{versionid} }
sub size { $_[0]->{filesize} }
sub width { $_[0]->{width} }
sub height { $_[0]->{height} }

# helper state subs
sub is_active { $_[0]->{state} eq 'A' }
sub is_deleted { $_[0]->{state} eq 'D' }

# Property method, loads our properties and fetches one when called, also
# handles updating and deleting them.
sub prop {
    my ( $self, $prop, $val ) = @_;

    my $u = $self->u;
    my $pobj = LJ::get_prop( media => $prop )
        or confess 'Attempted to get/set invalid media property';
    my $propid = $pobj->{id};

    unless ( $self->{_loaded_props} ) {
        my $props = $u->selectall_hashref(
            q{SELECT propid, value FROM media_props WHERE userid = ? AND mediaid = ?},
            'propid', undef, $self->{userid}, $self->{mediaid}
        );
        confess $u->errstr if $u->err;

        $self->{_props} = {
            map { $_->{propid} => $_->{value} } values %$props
        };
        $self->{_loaded_props} = 1;
    }

    # Getting an argument if they didn't provide a third. If they did, however,
    # then this fails and we go into the set logic.
    return $self->{_props}->{$propid} if scalar @_ == 2;

    # Setting logic. Delete vs update.
    if ( defined $val ) {
        $u->do(q{REPLACE INTO media_props (userid, mediaid, propid, value)
                 VALUES (?, ?, ?, ?)},
               undef, $self->{userid}, $self->{mediaid}, $propid, $val);
        confess $u->errstr if $u->err;

        return $self->{_props}->{$propid} = $val;
    } else {
        $u->do(q{DELETE FROM media_props WHERE userid = ? AND mediaid = ?
                   AND propid = ?},
               undef, $self->{userid}, $self->{mediaid}, $propid);
        confess $u->errstr if $u->err;

        delete $self->{_props}->{$propid};
        return undef;
    }
}

# construct a URL for this resource
sub url {
    my ( $self, %opts ) = @_;

    # If we're using a version (versionid defined) then we want to insert the
    # width and height to the URL.
    my $extra = $opts{extra} // '';
    if ( $self->{mediaid} != $self->{versionid} ) {
        $extra .= ( $self->{url_width} // $self->{width} ) . 'x' .
            ( $self->{url_height} // $self->{height} ) . '/';
    }

    return $self->u->journal_base . '/file/' . $extra . $self->{displayid} .
        '.' . $self->{ext};
}

# construct a URL for the fullsize version of this url. This is the same as
# url if the object is the orignal, fullsize version, but returns the url of
# the original if we're using version of it.
sub full_url {
    my $self = $_[0];

    return $self->u->journal_base . '/file/' . $self->{displayid} .
        '.' . $self->{ext};
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

    my $u = $self->u
        or croak 'Sorry, unable to load the user.';

    $u->do( q{UPDATE media SET state = 'D' WHERE userid = ? AND mediaid = ?},
            undef, $u->id, $self->id );
    confess $u->errstr if $u->err;

    $self->{state} = 'D';

    DW::BlobStore->delete( media => $self->mogkey );

    return 1;
}

# change the security of this item. returns 0/1 for successfulness.
sub set_security {
    my ( $self, %opts ) = @_;
    return 0 if $self->is_deleted;

    my $security = $opts{security};
    confess 'Invalid argument hash passed to set_security.'
        unless defined $security;

    my $mask = 0;
    if ( $security eq 'usemask' ) {
        # default allowmask of 0 unless defined otherwise
        $opts{allowmask} //= 0;
        $mask = int $opts{allowmask};
    }

    if ( $security =~ /^(?:friends|access)$/ ) {
        $security = 'usemask';
        $mask = 1;
    }
    confess 'Invalid security type passed to set_security.'
        unless $security =~ /^(?:private|public|usemask)$/;

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
