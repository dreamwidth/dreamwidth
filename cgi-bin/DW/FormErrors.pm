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

use DW::Request;
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
       ml_key => $error_ml,
    };
    $error->{ml_args} = $args if $args;

    $self->{_data}->add( $key || "", $error );
}

=head2 C<< $self->add_string( $key, $hardcoded_string ) >>

Adds a string for the given form field (key).

Use this only if you have a hardcoded string, such as one in a variable in the site config.
Otherwise, $self->add is preferred.

=cut
sub add_string {
    my ( $self, $key, $hardcoded_string ) = @_;

    my $error = {
        message => $hardcoded_string,
    };

    $self->{_data}->add( $key || "", $error );
}


=head2 C<< $self->get( $key ) >>

Return a list of errors for the given form field (key)

Errors are a hashref which contain:

=over

=item B< message >
the full string of the error message

=item B< ml_key > (optional)
the ml key used to generate the error message. May not exist if we
used $self->add_string

=item B< ml_args > (optional)
arguments for the ml string, as a hashref

=back


=cut
sub get {
    my ( $self, $key ) = @_;

    my @errors = $self->{_data}->get_all( $key );
    foreach my $error ( @errors ) {
        $error->{message} ||= LJ::Lang::ml( $self->_absolute_ml_code( $error->{ml_key} ), $error->{ml_args} );
    }

    # using an array slice to force it to return as a list, even if in scalar context
    # (so if it's called in scalar context, we just pull off the first error...)
    return @errors[0...$#errors];
}

=head2 C<< $self->get_all >>

Get all the errors in the order that were added.

Returns a reference to a list:

[
    { "key" => $key, "message" => $message },
    { "key" => $key, "message" => $message, ml_key => $error_ml, ml_args => { arg1 => value } },
]

Duplicate keys are preserved

=cut
sub get_all {
    my ( $self ) = @_;

    my @errors;
    $self->{_data}->each( sub {
                my $error = {
                    key     => $_[0],
                };
                $error->{ml_key} = $self->_absolute_ml_code( $_[1]->{ml_key} )
                    if $_[1]->{ml_key};
                $error->{ml_args} = $_[1]->{ml_args} if $_[1]->{ml_args};

                $error->{message} = $_[1]->{message}
                    || LJ::Lang::ml( $error->{ml_key}, $error->{ml_args} );

                push @errors, $error;
            } );

    return \@errors;
}


# converts relative ml codes to absolute ones (including filename)
# needs to be called when getting, rather than when adding
# because that's when we know the filename we're in
sub _absolute_ml_code {
    my ( $self, $error_ml ) = @_;

    my $r = DW::Request->get;
    my $ml_scope = $r ? $r->note( "ml_scope" ) : "";
    $error_ml =  $ml_scope . $error_ml
        if rindex( $error_ml, '.', 0 ) == 0;

    return $error_ml;
}

=head2 C<< $self->exist >>

Returns 1 if there are errors to display; 0 if none

=cut
sub exist {
    my ( $self ) = @_;

    return scalar $self->{_data}->keys ? 1 : 0;
}
1;
