#!/usr/bin/perl
#
# DW::Worker::ContentImporter::Local::Bio
#
# Local data utilities to handle importing of bio data into the local site.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Worker::ContentImporter::Local::Bio;
use strict;

use Carp qw/ croak /;

=head1 NAME

DW::Worker::ContentImporter::Local::Bio - Local data utilities for bio fields

=head1 Bio

These functions are part of the Saving API for bio fields.

=head2 C<< $class->merge_interests( $user, $hashref, $interests ) >>

$interests is an arrayref of strings of the interest names.

=cut

sub merge_interests {
    my ( $class, $u, $ints ) = @_;

    my $old_interests = $u->interests;

    my @all_ints = keys %$old_interests;

    foreach my $int ( @$ints ) {
        push @all_ints, lc( $int ) unless defined( $old_interests->{$int} );
    }

    $u->set_interests( \@all_ints );
}

=head2 C<< $class->merge_bio_items( $user, $hashref, $items ) >>

$items is a hashref of bio items.

=cut

sub merge_bio_items {
    my ( $class, $u, $items ) = @_;

    $u->set_bio( $items->{'bio'} ) if defined( $items->{'bio'} );

    foreach my $prop ( qw/ icq jabber yahoo journaltitle journalsubtitle / ) {
        $u->set_prop( $prop => $items->{$prop} )
            if defined $items->{$prop};
    }

    if ( defined $items->{homepage} ) {
        $u->set_prop( url => $items->{'homepage'}->{'url'} );
        $u->set_prop( urlname => $items->{'homepage'}->{'title'} );
    }
}

=head1 AUTHORS

=over

=item Andrea Nall <anall@andreanall.com>

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut


1;
