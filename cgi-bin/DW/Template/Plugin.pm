#!/usr/bin/perl
#
# DW::Template::Plugin
#
# Template Toolkit plugin for Dreamwidth
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010-2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Template::Plugin;
use base 'Template::Plugin';
use strict;

use DW::Template::Filters;
use DW::Template::VMethods;

=head1 NAME

DW::Template::Plugin - Template Toolkit plugin for Dreamwidth

=head1 SYNOPSIS

=cut

sub load {
    return $_[0];
}

sub new {
    my ( $class, $context, @params ) = @_;

    my $self = bless {
        _CONTEXT => $context,
    }, $class;

    $context->define_filter( 'ml', [ \&DW::Template::Filters::ml, 1 ] );
    $context->define_filter( 'js', [ \&DW::Template::Filters::js, 1 ] );

    return $self;
}

=head1 METHODS

=head2 need_res

Render a template to a string.

    [% dw.need_res( 'stc/some.css' ) %]

=cut

sub need_res {
    my $self = shift;
    my $opts = ref $_[0] eq 'HASH' ? shift : {};
    my @res = ref $_[0] eq 'ARRAY' ? @{ $_[0] } : @_;
    return LJ::need_res( $opts, @res );
}

=head2 active_resource_group

Set the resource group to be loaded for this page.

=cut

sub active_resource_group {
    return LJ::set_active_resource_group( $_[1] );
}

=head2 ml_scope

Get or set the ML scope of the template

    # store the old value
    [% old_scope = dw.ml_scope() %]

    # CALL forces us to ignore the returned value, and not print it out
    [% CALL dw.ml_scope( '/foo.tt' ) %]
    [% CALL dw.ml_scope( old_scope ) %]

=cut

sub ml_scope {
    my $r = DW::Request->get;
    return $#_ == 1 ? $r->note( 'ml_scope', $_[1] ) : $r->note( 'ml_scope' );
}

=head2 form_auth

Return a HTML form element (input type=hidden) that contains the proper code for
authenticating this form on POST.  This is required to be on all forms to help
prevent XSS and other exploits.

    <form ...>
        # within the form somewhere...
        [% dw.form_auth() %]
    </form>

=cut

sub form_auth {
    return LJ::form_auth();
}

=head2 create_url

Wrapper around LJ::create_url

    [% dw.create_url( undef, keep_args => 1 ) %]

=cut

sub create_url {
    return LJ::create_url( $_[1], %{ $_[2] || {} } );
}


sub img {
    my $self = shift;
    return LJ::img(@_);
}
=head1 AUTHOR

=over

=item Andrea Nall <anall@andreanall.com>

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2010-2011 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
