#!/usr/bin/perl
#
# DW::Worker::ContentImporter
#
# Generic helper functions for Content Importers
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Worker::ContentImporter;

=head1 NAME

DW::Worker::ContentImporter - Generic helper functions for Content Importers

The job running itself (outcomes, notifications, retries, chaining) is in
L<DW::Importer::Job>, which this class inherits.

=cut

use strict;
use v5.10;

use LJ::Protocol;
use LJ::Talk;

use base 'DW::Importer::Job';

=head1 Saving API

All Saving API functions take as the first two options the target user
option, followed by a consistent hashref passed to every function.

=head2 C<< $class->merge_trust( $user, $hashref, $friends ) >>

$friends is a reference to an array of hashrefs, with each hashref with the following format:

  {
      userid => ...,        # local userid of the friend
      groupmask => 1,       # groupmask
  }

Returns true if all grants were saved, false otherwise.

=cut

sub merge_trust {
    my ( $class, $u, $opts, $friends ) = @_;
    foreach my $friend (@$friends) {
        my $to_u = LJ::load_userid( $friend->{userid} ) or return 0;
        return 0
            unless $u->add_edge( $to_u, trust => { mask => $friend->{groupmask}, nonotify => 1, } );
    }
    return 1;
}

=head2 C<< $class->merge_watch( $user, $hashref, $friends ) >>

$friends is a reference to an array of hashrefs, with each hashref with the following format:

  {
      userid => ...,        # local userid of the friend
      fgcolor => '#ff0000', # foreground color
      bgcolor => '#00ff00', # background color
  }

=cut

sub merge_watch {
    my ( $class, $u, $opts, $friends ) = @_;
    foreach my $friend (@$friends) {
        my $to_u = LJ::load_userid( $friend->{userid} );
        $u->add_edge(
            $to_u,
            watch => {
                nonotify => 1,
                fgcolor  => LJ::color_todb( $friend->{fgcolor} ),
                bgcolor  => LJ::color_todb( $friend->{bgcolor} ),
            }
        );
    }
}

1;
