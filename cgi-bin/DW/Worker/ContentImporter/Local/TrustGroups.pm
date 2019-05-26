#!/usr/bin/perl
#
# DW::Worker::ContentImporter::Local::TrustGroups
#
# Local data utilities to handle importing of trust groups to the local site.
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

package DW::Worker::ContentImporter::Local::TrustGroups;
use strict;

=head1 NAME

DW::Worker::ContentImporter::Local::TrustGroups - Local data utilities for trust groups

=head1 Trust Groups

These functions are part of the Saving API for trust groups.

=head2 C<< $class->merge_trust_groups( $user, $groups ) >>

$groups is a reference to an array of hashrefs, with each hashref with the following format:

  {
    name => 'Friend Group',  # name of the group
    sortorder => 50,         # integer sort order
    public => 1,             # Is this public or not
    id => 1,                 # The ID the group uses
  }

Returns a map of old-id to new-id.

=cut

sub merge_trust_groups {
    my ( $class, $u, $groups ) = @_;

    # map our existing groups to name->id so we can use this list
    # later to map groups if we've imported before
    my %name_map;
    my $cur_groups = $u->trust_groups || {};
    foreach my $id ( keys %$cur_groups ) {
        $name_map{ $cur_groups->{$id}->{groupname} } = $id;
    }

    # now map new groups
    my %map;
    foreach my $group ( @{ $groups || [] } ) {

        # we assume the incoming group is valid
        my $name   = $group->{name};
        my $sort   = $group->{sortorder};
        my $public = $group->{public};

        my $id = 0;

        if ( defined $name_map{$name} ) {
            $id = $name_map{$name};
            $u->edit_trust_group(
                id        => $id,
                groupname => $name,
                sortorder => $sort,
                is_public => $public
            );
        }
        else {
            $id = $u->create_trust_group(
                groupname => $name,
                sortorder => $sort,
                is_public => $public
            );
        }

        $map{ $group->{id} } = $id if $id;
    }

    return \%map;
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
