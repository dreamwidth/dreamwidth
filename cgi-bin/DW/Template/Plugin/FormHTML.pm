#!/usr/bin/perl
#
# DW::Template::Plugin::FormHTML
#
# Template Toolkit plugin to generate HTML elements with preset values.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Template::Plugin::FormHTML;
use base 'Template::Plugin';
use strict;

use Hash::MultiValue;

=head1 NAME

DW::Template::Plugin::FormHTML - Template Toolkit plugin to generate HTML elements
with preset values

=head1 SYNOPSIS

The form plugin generates HTML elements with attributes suitably escaped, and values automatically prepopulated, depending on the form's data field.

The "data" field is a hashref, with the keys being the form element's name, and the values being the form element's desired value.

If a "formdata" property is available via the context, this is used to automatically populate the plugin's data field. It may be either a hashref or an instance of Hash::MultiValue.
=cut

sub load {
    return $_[0];
}

sub new {
    my ( $class, $context, @params ) = @_;

    my $data;
    if ( $context ) {
        my $formdata = $context->stash->{formdata};
        $data = ref $formdata eq "Hash::MultiValue" ? $formdata : Hash::MultiValue->from_mixed( $formdata );
    }

    my $self = bless {
        _CONTEXT => $context,
        data     => $data,
    }, $class;

    return $self;
}

=head1 METHODS

=cut

=head2 Common Arguments

All methods which generate an HTML element can accept the following optional arguments:
=item default - default value to use. Does not override the value of a previous form submission
=item value - value to apply to the form element. Does override any previous form submissions
=item selected - (for checkbox, radio) - whether the form element was selected or not
               - (for select) - the selected option in the dropdown

=item label - text for a label, which is paired with the form element if an id is provided
=item labelclass - class for a label

=item id - id of the element. Highly recommended, especially if you have a label
=item name - name of the form element. You'll probably really want this
=item class - CSS class of the form element

=item (other valid HTML attributes)
=cut

=head2 [% form.checkbox( label="A label", id="elementid", name="elementname", .... ) %]

Return a checkbox with a matching label, if provided. Values are prepopulated by the plugin's datasource.

=cut

sub checkbox {
    my ( $self, $args ) = @_;

    my $ret = "";

    if ( ! defined $args->{selected} && $self->{data} ) {
        my %selected = map { $_ => 1 } ( $self->{data}->get_all( $args->{name} ) );
        $args->{selected} = $selected{$args->{value}};
    }

    $args->{labelclass} ||= "checkboxlabel";
    $args->{class} ||= "checkbox";

    # makes the form element use the default or an explicit value...
    my $label_html = $self->_process_value_and_label( $args, use_as_value => "selected", noautofill => 1 );

    $ret .= LJ::html_check( $args );
    $ret .= $label_html;

    return $ret;
}

=head2 [% form.hidden( name =... ) %]

Return a hidden form element. Values are prepopulated by the plugin's datasource.

=cut

sub hidden {
    my ( $self, $args ) = @_;

    $self->_process_value_and_label( $args );
    return LJ::html_hidden( $args );
}

=head2 [% form.radio( label = ... ) %]

Return a radiobutton with a matching label, if provided. Values are prepopulated by the plugin's datasource.

=cut

sub radio {
    my ( $self, $args ) = @_;

    $args->{type} = "radio";

    my $ret = "";

    if ( ! defined $args->{selected} && $self->{data} ) {
        my %selected = map { $_ => 1 } $self->{data}->get_all( $args->{name} );
        $args->{selected} = $selected{$args->{value}};
    }

    $args->{labelclass} ||= "radiolabel";
    $args->{class} ||= "radio";

    # makes the form element use the default or an explicit value...
    my $label_html = $self->_process_value_and_label( $args, use_as_value => "selected", noautofill => 1 );

    $ret .= LJ::html_check( $args );
    $ret .= $label_html;

    return $ret;

}

=head2 [% form.select( label="A Label", id="elementid", name="elementname", items=[array of items], ... ) %]

Return a select dropdown with a list of options, and matching label if provided. Values are prepopulated
by the plugin's datasource.

=cut
sub select {
    my ( $self, $args ) = @_;

    my $items = delete $args->{items};
    $args->{class} ||= "select";

    my $ret = "";
    $ret .= $self->_process_value_and_label( $args, use_as_value => "selected" );
    $ret .= LJ::html_select( $args, @{$items || []} );
    return $ret;
}

=head2 [% form.submit( name =... ) %]

Return a button for submitting a form. Values are prepopulated by the plugin's datasource.

=cut

sub submit {
    my ( $self, $args ) = @_;

    $args->{class} ||= "submit";

    $self->_process_value_and_label( $args );
    return LJ::html_submit( delete $args->{name}, delete $args->{value}, $args );
}

=head2 [% form.textarea( label=... ) %]

Return a textarea with a matching label, if provided. Values are prepopulated
by the plugin's datasource.

=cut

sub textarea {
    my ( $self, $args ) = @_;

    $args->{class} ||= "text";

    my $ret = "";
    $ret .= $self->_process_value_and_label( $args );
    $ret .= LJ::html_textarea( $args );

    return $ret;
}


=head2 [% form.textbox( label="A Label", id="elementid", name="elementname", ... ) %]

Return a textbox (input type="text") with a matching label, if provided. Values
are prepopulated by the plugin's datasource.

=cut

sub textbox {
    my ( $self, $args ) = @_;

    $args->{class} ||= "text";

    my $ret = "";
    $ret .= $self->_process_value_and_label( $args );
    $ret .= LJ::html_text( $args );

    return $ret;
}

=head2 [% form.password( label="A Label", id="elementid", name="elementname",... ) %]

Return a password field with a matching label, if provided. Values are never prepopulated

=cut
sub password {
    my ( $self, $args ) = @_;

    $args->{type} = "password";
    $args->{class} ||= "text";

    my $ret = "";
    $ret .= $self->_process_value_and_label( $args, noautofill => 1 );
    $ret .= LJ::html_text( $args );

    return $ret;

}


# populate the element's value, modifying the $args hashref
# return the label HTML if applicable
sub _process_value_and_label {
    my ( $self, $args, %opts ) = @_;

    my $valuekey = $opts{use_as_value} || "value";
    my $default = delete $args->{default};

    if ( defined $args->{$valuekey} ) {
        # explicitly override with a value when we created the form element
        # do nothing! Just use what we passed in
    } else {
        # we didn't pass in an explicit value; check our data source (probably form post)
        if ( $self->{data} && ! $opts{noautofill} && $args->{name} ) {
            $args->{$valuekey} = $self->{data}->{$args->{name}};
        }

        # no data source, value not set explicitly, use a default if provided
        $args->{$valuekey} ||= $default;
    }

    my $label_html = "";
    my $label = delete $args->{label};
    my $labelclass = delete $args->{labelclass} || "";
    $label_html = LJ::labelfy( $args->{id} || "", LJ::ehtml( $label ), $labelclass )
        if defined $label;

    return $label_html || "";
}

=head1 AUTHOR

=over

=item Afuna <coder.dw@afunamatata.com>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2011 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
