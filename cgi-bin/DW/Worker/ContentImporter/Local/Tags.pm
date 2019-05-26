#!/usr/bin/perl
#
# DW::Worker::ContentImporter::Local::Tags
#
# Local data utilities to handle importing of tags into the local site.
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

package DW::Worker::ContentImporter::Local::Tags;
use strict;

=head1 NAME

DW::Worker::ContentImporter::Local::Tags - Local data utilities for tags

=head1 Tags

These functions are part of the Saving API for tags.

=head2 C<< $class->merge_tags( $u, $tags ) >>

$tags is an arrayref of strings of the tag names.

=cut

sub merge_tags {
    my ( $class, $u, $tags ) = @_;

    foreach my $tag ( @{ $tags || [] } ) {
        LJ::Tags::create_usertag( $u, $tag->{name},
            { ignore_max => 1, display => $tag->{display} } );
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
