#!/usr/bin/perl
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::FormErrors;

use strict;


use Hash::MultiValue;

=head1 NAME

DW::FormErrors - Manages error messages that should be displayed when
validating form input

=head1 SYNOPSIS

This module handles errors that come up in form validation. It should be
created and populated in the controller, then passed to the template

Errors can be pulled out in the order that they were added, for batch
display of errors, or by key, for displaying the error along with its
relevant form-field


    my $errors = DW::FormErrors->new;

    # adds an error for input named `fieldname`
    $errors->add( "fieldname", ".error.ml_string" );

    # add the error object to the template variables
    DW::Template->render_template( "...", {
        formdata    => $r->post_args,
        errors      => $errors,
    });

The template then takes care of displaying the errors. On Foundation pages,
this will be handled for you automatically: all you need to do is pass in the
`errors` variable.

=cut

=head2 C<< $class->new >>

Returns a new DW::FormErrors object

=cut
sub new {
    my ( $class ) = @_;

    return bless {
        _data => Hash::MultiValue->new,
    };
}

=head2 C<< $self->add( $key, $error_ml ) >>

Adds an error ml code for the given form field (key)

=cut
sub add {
    my ( $self, $key, $error_ml, $args ) = @_;

    my $error = {
        message => $error_ml,
    };
    $error->{args} = $args if $args;

    $self->{_data}->add( $key, $error );
}

=head2 C<< $self->get( $key ) >>

Return a list of errors for the given form field (key)

Errors are a hashref which contain:

=over
=item B< message >
error ml code

=item B< args > (optional)
arguments for the ml string, as a hashref

=back


=cut
sub get {
    my ( $self, $key ) = @_;

    return $self->{_data}->get_all( $key );
}

=head2 C<< $self->get_all >>

Get all the errors in the order that were added.

Returns a reference to a list:

[
    { "key" => $key, "message" => $error_ml },
    { "key" => $key, "message" => $error_ml, args => { arg1 => value } },
]

Duplicate keys are preserved

=cut
sub get_all {
    my ( $self ) = @_;

    my @errors;
    $self->{_data}->each( sub { push @errors, { key => $_[0], %{$_[1]} } } );

    return \@errors;
}

=head2 C<< $self->exist >>

Returns 1 if there are errors to display; 0 if none

=cut
sub exist {
    my ( $self ) = @_;

    return scalar $self->{_data}->keys ? 1 : 0;
}
1;