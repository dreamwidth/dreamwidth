#!/usr/bin/perl
#
# DW::Template::Plugin::FormHTML
#
# Template Toolkit plugin to generate HTML elements with preset values.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2011-2013 by Dreamwidth Studios, LLC.
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

The form plugin generates HTML elements with attributes suitably escaped, and values
automatically prepopulated, depending on the form's data field.

The "data" field is a hashref, with the keys being the form element's name, and the values
being the form element's desired value.

If a "formdata" property is available via the context, this is used to automatically
populate the plugin's data field. It may be either a hashref or an instance of Hash::MultiValue.

=cut

sub load {
    return $_[0];
}

sub new {
    my ( $class, $context, @params ) = @_;

    my $data;
    my $errors;
    if ( $context ) {
        my $stash = $context->stash;
        my $formdata = $stash->{formdata};
        $data = ref $formdata eq "Hash::MultiValue" ? $formdata : Hash::MultiValue->from_mixed( $formdata );

        my $formerrors = $stash->{errors};
        $errors = $formerrors if $formerrors && ref $formerrors eq "DW::FormErrors" && $formerrors->exist;
    }

    my $r = DW::Request->get;

    my $self = bless {
        _CONTEXT => $context,
        data     => $data,
        errors   => $errors,
        did_post => $r && $r->did_post,
        _id_gen_counter => 0,
    }, $class;

    return $self;
}

=head1 METHODS

=cut

=head2 Common Arguments

All methods which generate an HTML element can accept the following optional arguments:

=over

=item default - default value to use. Does not override the value of a previous form submission
                The default value will most likely come from settings stored in the DB.
                It may also be a hardcoded initial value.

=item value - value to apply to the form element. Does override any previous form submissions

=item selected - (for checkbox, radio) - whether the form element was selected or not
               - (for select) - the selected option in the dropdown

=item label - text for a label, which is paired with the form element if an id is provided

=item labelclass - class for a label

=item id - id of the element. Highly recommended, especially if you have a label

=item name - name of the form element. You'll probably really want this

=item class - CSS class of the form element

=item (other valid HTML attributes)

=back

=head2 [% form.checkbox( label="A label", id="elementid", name="elementname", .... ) %]

Return a checkbox with a matching label, if provided. Values are prepopulated by the plugin's datasource.

=cut

sub checkbox {
    my ( $self, $args ) = @_;

    my $ret = "";

    if ( ! defined $args->{selected} && $self->{data} ) {
        my %selected;
        if ( defined $args->{name} ) {
            my @selargs = grep { defined } ( $self->{data}->get_all( $args->{name} ) );
            %selected = map { $_ => 1 } @selargs;
        }
        if ( defined $args->{value} ) {
            $args->{selected} = $selected{$args->{value}};
        } elsif ( $LJ::IS_DEV_SERVER ) {
            warn "DW::Template::Plugin::FormHTML::checkbox has undefined argument 'value'";
        }
    }

    $args->{labelclass} ||= "checkboxlabel";
    $args->{class} ||= "checkbox";
    $args->{id} ||= $self->generate_id( $args );

    # makes the form element use the default or an explicit value...
    my $label_html = $self->_process_value_and_label( $args, use_as_value => "selected", noautofill => 1 );

    $ret .= LJ::html_check( $args );
    $ret .= $label_html;

    return $ret;
}

=head2 [% form.checkbox_nested( label="A label", id="elementid", name="elementname", .... ) %]

Return a checkbox nested within a label, if provided. Values are prepopulated by the plugin's datasource.

Additional option:

=over

=item remember_old_state - 1 if you want to include a hidden element containing the checkbox's value on page load.
    Useful for cases when you have a list of items, and you want to know if the checkbox started out unchecked.
    When it's unchecked, the checkbox doesn't get submitted, equivalent to it not being on the page in the first place.
    So we might want to keep track of the old value so we "remember" that we need to handle the toggle

=back

=cut

sub checkbox_nested {
    my ( $self, $args ) = @_;

    my $ret = "";

    if ( ! defined $args->{selected} && $self->{data} ) {
        my %selected;
        if ( defined $args->{name} ) {
            my @selargs = grep { defined } ( $self->{data}->get_all( $args->{name} ) );
            %selected = map { $_ => 1 } @selargs;
        }
        if ( defined $args->{value} ) {
            $args->{selected} = $selected{$args->{value}};
        } elsif ( $LJ::IS_DEV_SERVER ) {
            warn "DW::Template::Plugin::FormHTML::checkbox_nested has undefined argument 'value'";
        }
    }

    $args->{class} ||= "checkbox";

    my $label = delete $args->{label};
    my $include_hidden = (delete $args->{remember_old_state} || 0) && $args->{selected};

    # makes the form element use the default or an explicit value...
    $self->_process_value_and_label( $args, use_as_value => "selected", noautofill => 1 );

    my $for = $args->{id} ? "for='$args->{id}'" : "";
    $ret .= "<label $for>" . LJ::html_check( $args ) . " $label</label>";
    $ret .= LJ::html_hidden( { name => $args->{name} . "_old" , value => $args->{value}} )
        if $include_hidden;

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
        my %selected;
        if ( defined $args->{name} ) {
            %selected = map { $_ => 1 } ( $self->{data}->get_all( $args->{name} ) );
        }
        if ( defined $args->{value} ) {
            $args->{selected} = $selected{$args->{value}};
        } elsif ( $LJ::IS_DEV_SERVER ) {
            warn "DW::Template::Plugin::FormHTML::radio has undefined argument 'value'";
        }
    }

    $args->{labelclass} ||= "radiolabel";
    $args->{class} ||= "radio";
    $args->{id} ||= $self->generate_id( $args );

    # makes the form element use the default or an explicit value...
    my $label_html = $self->_process_value_and_label( $args, use_as_value => "selected", noautofill => 1 );

    $ret .= LJ::html_check( $args );
    $ret .= $label_html;

    return $ret;

}

=head2 [% form.radio_nested( label = ... ) %]

Return a radiobutton nested within a label, if provided. Values are prepopulated by the plugin's datasource.

=cut

sub radio_nested {
    my ( $self, $args ) = @_;

    $args->{type} = "radio";

    my $ret = "";
    if ( ! defined $args->{selected} && $self->{data} ) {
        my %selected;
        if ( defined $args->{name} ) {
            %selected = map { $_ => 1 } ( $self->{data}->get_all( $args->{name} ) );
        }
        if ( defined $args->{value} ) {
            $args->{selected} = $selected{$args->{value}};
        } elsif ( $LJ::IS_DEV_SERVER ) {
            warn "DW::Template::Plugin::FormHTML::radio_nested has undefined argument 'value'";
        }
    }

    $args->{class} ||= "radio";

    my $label = delete $args->{label};

    # makes the form element use the default or an explicit value...
    $self->_process_value_and_label( $args, use_as_value => "selected", noautofill => 1 );

    my $for = $args->{id} ? "for='$args->{id}'" : "";
    $ret .= "<label $for>" . LJ::html_check( $args ) . " $label</label>";
}

=head2 [% form.select( label="A Label", id="elementid", name="elementname", items=[array of items], ... ) %]

Return a select dropdown with a list of options, and matching label if provided. Values are prepopulated
by the plugin's datasource.

=cut
sub select {
    my ( $self, $args ) = @_;

    my $items = delete $args->{items};
    $args->{class} ||= "select";
    $args->{id} ||= $self->generate_id( $args );

    my $errors = $self->_process_errors( $args );
    my $hint = $self->_process_hint( $args );

    my $ret = "";
    $ret .= $self->_process_value_and_label( $args, use_as_value => "selected" );
    $ret .= LJ::html_select( $args, @{$items || []} );

    $ret .= $errors;
    $ret .= $hint;

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
    $args->{id} ||= $self->generate_id( $args );

    my $errors = $self->_process_errors( $args );
    my $hint = $self->_process_hint( $args );

    my $ret = "";
    $ret .= $self->_process_value_and_label( $args );
    $ret .= LJ::html_textarea( $args );

    $ret .= $errors;
    $ret .= $hint;

    return $ret;
}


=head2 [% form.textbox( label="A Label", id="elementid", name="elementname", ... ) %]

Return a textbox (input type="text") with a matching label, if provided. Values
are prepopulated by the plugin's datasource.

=cut

sub textbox {
    my ( $self, $args ) = @_;


    $args->{class} ||= "text";
    $args->{id} ||= $self->generate_id( $args );

    my $hint = $self->_process_hint( $args );
    my $errors = $self->_process_errors( $args );

    my $ret = "";
    $ret .= $self->_process_value_and_label( $args );
    $ret .= LJ::html_text( $args );

    $ret .= $errors;
    $ret .= $hint;

    return $ret;
}

=head2 [% form.password( label="A Label", id="elementid", name="elementname",... ) %]

Return a password field with a matching label, if provided. Values are never prepopulated

=cut
sub password {
    my ( $self, $args ) = @_;

    $args->{type} = "password";
    $args->{class} ||= "text";
    $args->{id} ||= $self->generate_id( $args );

    my $hint = $self->_process_hint( $args );
    my $errors = $self->_process_errors( $args );

    my $ret = "";
    $ret .= $self->_process_value_and_label( $args, noautofill => 1 );
    $ret .= LJ::html_text( $args );

    $ret .= $errors;
    $ret .= $hint;

    return $ret;

}

# generates a unique id for a form element
# ensures that we can easily associate the form element to its label
sub generate_id {
    my ( $self, $args ) = @_;
    return "id-" . $args->{name} . "-" . $self->{_id_gen_counter}++;
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
        $args->{$valuekey} //= $default unless $self->{did_post};
    }

    my $label_html = "";
    my $label = delete $args->{label};
    my $labelclass = delete $args->{labelclass} || "";
    my $noescape = delete $args->{noescape};

    if ( defined $label ) {
        # don't ehtml the label text if noescape is specified
        $label = LJ::ehtml( $label ) unless $noescape;
        $label_html = LJ::labelfy( $args->{id}, $label, $labelclass );
    }

    return $label_html || "";
}

sub _process_hint {
    my ( $self, $args ) = @_;

    my $hint = delete $args->{hint};
    my $describedby;
    if ( $hint ) {
        $describedby = $args->{id} ? "$args->{id}-hint" : "";
        $args->{"aria-describedby"} = $describedby;
    }

    return $hint ? qq{<span class="form-hint" id='$describedby'>$hint</span>} : "";
}

sub _process_errors {
    my ( $self, $args ) = @_;

    my @errors;
    @errors = $self->{errors}->get( $args->{name} ) if $self->{errors};

    $args->{class} .= " error" if @errors;

    my $ret = "";
    foreach my $error ( @errors ) {
        $ret .= qq!<small class="error">$error->{message}</small>!;
    }
    return $ret;
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
