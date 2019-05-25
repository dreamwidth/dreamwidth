#!/usr/bin/perl
#
# DW::StatData - Abstract superclass for statistics modules
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::StatData;

=head1 NAME

DW::StatData - Abstract superclass for statistics modules

=head1 SYNOPSIS

    use DW::StatStore;  # to retrieve stored statistics from the database
    use DW::StatData;   # to serve as an API for gathering the data
    # load all the available DW::StatData::* submodules
    LJ::ModuleLoader::require_subclasses( 'DW::StatData' );

    # get the latest set of pony statistics
    my $ponies = DW::StatData::Ponies->load_latest( DW::StatStore->get( "ponies" ) );

    # how many ponies are currently sparkly?
    $ret .= $ponies->value( "sparkly" );

    # load statistics for ponies over the past 30 days
    my $ponies_history = DW::StatData::Ponies->load( DW::StatStore->get( "ponies", 30 ) );
    
    # get the number of sparkly ponies 15 days ago
    $ret .= $ponies_history->{15}->value( "sparkly" );

=cut

use strict;
use warnings;
use Carp qw( confess );
use POSIX qw( floor );

use fields qw( data );

=head1 API

=head2 C<< $self->category >>

Returns the category of statistics handled by this module. Subclasses should override this.

=cut

sub category {
    confess "'category' should be implemented by subclass";
}

=head2 C<< $self->name >>

Returns the pretty name of this category. Subclasses should override this.

=cut

sub name {
    confess "'name' should be implemented by subclass";
}

=head2 C<< $self->keylist >>

Returns an array of available keys within this category. Subclasses should override this.

=cut

sub keylist {
    confess "'keylist' should be implemented by subclass";
}

=head2 C<< $self->value( $key ) >>

Given a key, returns a value.

=cut

sub value {
    my ( $self, $key ) = @_;
    return $self->data->{$key};
}

=head2 C<< $self->data >>

Returns a hashref of the statistics data under this category.

=cut

sub data {
    return $_[0]->{data};
}

=head2 C<< $class->collect( @keys ) >>

Collects data from a specific table or set of tables for statistics under this
category. @keys is the list of keys to collect statistics for. Returns a
{ key => value } hashref, like the ->data object method. Subclasses must
implement this.

=cut

sub collect {
    confess "'collect' should be implemented by subclass";
}

=head2 C<< $class->new( $key1 => $value, ... ) >>

Initialize this row of stat data, given a hash of statkey-value pairs

=cut

sub new {
    my ( $self, %data ) = @_;

    unless ( ref $self ) {
        $self = fields::new($self);
    }
    while ( my ( $k, $v ) = each %data ) {
        $self->{$k} = $v;
    }

    return $self;
}

=head2 C<< $class->load( { $timestampA => { $key1 => $value1, ... }, $timestampB => ... } ) >>

Given a hashref of timestamps mapped to data rows, returns a hashref of DW::StatData::* objects. Input timestamps are time that row of statistics was collected; returned hash keys are how many days ago this data was collected.

=cut

sub load {
    my ( $class, $rows ) = @_;
    my $days_ago = sub {
        my $timestamp = $_[0];
        return floor( ( time() - $timestamp ) / ( 24 * 60 * 60 ) );
    };

    my $ret;
    while ( my ( $timestamp, $data ) = each %$rows ) {

        # does not protect against multiple versions of the data collected on the same day?
        $ret->{ $days_ago->($timestamp) } = $class->new( data => $data );
    }
    return $ret;
}

=head2 C<< $class->load_latest( ... ) >>

Accepts the same arguments as $class->load, but returns only the latest row

=cut

sub load_latest {
    my $self = shift;
    my $rows = $self->load(@_);
    my @sorted;
    if ( defined $rows && %$rows ) {
        @sorted = sort { $a <=> $b } keys %$rows;
        return $rows->{ $sorted[0] };
    }

    return undef;
}

=head1 BUGS

Multiple versions of the data collected on the same day will be collapsed into one day.

=head1 AUTHORS

Afuna <coder.dw@afunamatata.com>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
