#!/usr/bin/perl
#
# DW::SiteScheme
#
# SiteScheme related functions
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

=head1 NAME

DW::SiteScheme - SiteScheme related functions

=head1 SYNOPSIS

=cut

package DW::SiteScheme;
use strict;

my %sitescheme_inheritance = (
    blueshift => 'common',
    celerity => 'common',
    common => 'global',
    'gradation-horizontal' => 'common',
    'gradation-vertical' => 'common',
    lynx => 'common',
);

my $default_sitescheme = "blueshift";

eval "use DW::SiteScheme::Local;";

# no POD, should only be called from Local module
# DW::SiteScheme->register_siteschemes( foo => 'bar' );
sub register_siteschemes {
    my ( $self, %data ) = @_;
    %sitescheme_inheritance = (
        %sitescheme_inheritance,
        %data
    );
}

# no POD, should only be called from Local module
# DW::SiteScheme->register_siteschemes( 'foo' );
sub register_default_sitescheme {
    $default_sitescheme = $_[1];
}

=head2 C<< DW::SiteScheme->determine_current_sitescheme >>

Determine the siteschehe, using the following in order:

=over

=item bml_use_scheme note

=item usescheme GET argument

=item BMLschemepref cookie

=item Default sitescheme

=item 'global'

=back

=cut

sub determine_current_sitescheme {
    my $r = DW::Request->get;

    my $rv;

    if ( defined $r ) {
        $rv = $r->note( 'bml_use_scheme' ) ||
            $r->get_args->{usescheme} ||
            $r->cookie( 'BMLschemepref' );
    }
    return $rv ||
        $default_sitescheme ||
        'global';
}

=head2 C<< DW::SiteScheme->get_sitescheme_inheritance( $scheme ) >>

Scheme defaults to the current sitescheme.

Returns the inheritance array, with the provided scheme being at the start of the list.

=cut

sub get_sitescheme_inheritance {
    my ( $self, $scheme ) = @_;
    $scheme ||= $self->determine_current_sitescheme;
    my @scheme;
    push @scheme, $scheme;
    push @scheme, $scheme while ( $scheme = $sitescheme_inheritance{$scheme} );
    return @scheme;
}

1;