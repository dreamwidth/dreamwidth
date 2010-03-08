#!/usr/bin/perl
#
# DW::Template::Plugin
#
# Template Toolkit plugin for Dreamwidth
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Template::Plugin;
use base 'Template::Plugin';
use strict;

use DW::Template::Filters;

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

    return $self;
}

=head1 METHODS

=head2 need_res

Render a template to a string.

    [% dw.need_res( 'stc/some.css' ); %]

=cut

sub need_res {
    my $self = shift;
    return LJ::need_res( @_ );
}

=head2 ml_scope

Set the ML scope of the template

    [% dw.ml_scope( '/foo.tt' ) %]

=cut

sub ml_scope {
    return DW::Request->get->note( 'ml_scope', $_[1] );
}

=head1 FILTERS

=head2 ml

Apply a ML string.

    [% '.foo' | ml(arg = 'bar') %]

=cut

=head1 AUTHOR

=over

=item Andrea Nall <anall@andreanall.com>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2010 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;