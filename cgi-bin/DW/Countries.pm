#!/usr/bin/perl
#
# DW::Countries
#
# Replacement for LJ::load_codes( { country => ... } )
#
# Authors:
#      Pau Amma <pauamma@dreamwidth.org>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Countries;

use strict;
use Locale::Codes::Country;

=head1 NAME

DW::Countries - Replacement for LJ::load_codes( { country => ... } )

=head1 DESCRIPTION

This is at this point just a replacement for
C<< LJ::load_codes( { country => ... } ) >>. It may become more in the future,
eg by taking on subcountry (state/province/etc...) management as well.

=head1 SYNOPSIS

  DW::Countries->load( \%countries ) # %countries = ( AF => 'Afghanistan', ... )

=head1 API

=head2 C<< DW::Countries->load( $hashref ) >>

Sets %$hashref to a hash of alpha-2 uppercase country code => country name for
all active country codes.

=cut

sub load {
    my ( $class, $countries ) = @_;

    %$countries = ();
    foreach my $code ( all_country_codes() ) {
        $countries->{ uc $code } = code2country( $code );
    }
    $countries->{UK} = $countries->{GB};
}

1;

=head1 AUTHORS

Pau Amma <pauamma@dreamwidth.org>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2014 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.
