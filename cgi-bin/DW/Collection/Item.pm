#!/usr/bin/perl
#
# DW::Collection::Item
#
# This is the base module to represent items in a collection.
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

package DW::Collection::Item;

use strict;
use Carp qw/ croak confess /;

use constant TYPE_MEDIA   => 1;
use constant TYPE_ENTRY   => 2;
use constant TYPE_COMMENT => 3;

sub new_from_row {
    my ( $class, %opts ) = @_;

    # simply bless and return then, we don't do anything smart here yet
    return bless \%opts, $class;
}

sub u           { $_[0]->{_u} ||= LJ::load_userid( $_[0]->{userid} ) }
sub userid      { $_[0]->{userid} }
sub id          { $_[0]->{colitemid} }
sub colid       { $_[0]->{colid} }
sub itemtype    { $_[0]->{itemtype} }
sub itemownerid { $_[0]->{itemownerid} }
sub itemid      { $_[0]->{itemid} }
sub logtime     { $_[0]->{logtime} }

# this returns an object for the thing we represent
sub resolve {
    my $self = $_[0];

    my $owneru = LJ::load_userid( $self->{itemownerid} );
    if ( $self->{itemtype} == TYPE_MEDIA ) {
        return DW::Media->new( user => $owneru, mediaid => $self->{itemid} );

    }
    elsif ( $self->{itemtype} == TYPE_ENTRY ) {

    }
    elsif ( $self->{itemtype} == TYPE_COMMENT ) {

    }

    croak 'Invalid type in resolution.';
}

1;
