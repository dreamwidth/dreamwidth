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

Returns a hashref with the count of rejected grants, or undef if a write should be retried.

=cut

sub merge_trust {
    my ( $class, $u, $opts, $friends ) = @_;
    my $rejected = 0;
    foreach my $friend (@$friends) {
        my $to_u  = LJ::load_userid( $friend->{userid} ) or return undef;
        my $trust = { mask => $friend->{groupmask}, nonotify => 1, policy_rejected => 0 };
        next if $u->add_edge( $to_u, trust => $trust );
        return undef unless $trust->{policy_rejected};
        $rejected++;
    }
    return { rejected => $rejected };
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
