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

  # examples of function usage

=cut

use strict;
use warnings;
use Carp qw( confess );

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

=head2 C<< $class->new( $category, $name, $key1 => $value, ... ) >>

Initialize

=cut

sub new {
    return fields::new( $_[0] );
}

=head1 BUGS

=head1 AUTHORS

Afuna <coder.dw@afunamatata.com>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
