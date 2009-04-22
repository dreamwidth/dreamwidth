#!/usr/bin/perl
#
# DW::StatStore
#
# Used for storing, loading, inserting, updating, etc stats.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Pau Amma <pauamma@cpan.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

=head1 NAME

DW::StatStore -- Statistics store update and retrieval

=head1 SYNOPSIS

  # Add timestamped line to pony stats
  DW::StatStore->add( 'ponies', total => 34738, sparkly => 45 )
      or die "Some error happened";
  # FIXME: define retrieval method(s)

=cut

package DW::StatStore;

use strict;
use warnings;
use LJ::Typemap;

=head1 API

=head2 C<< $class->add( $category, $key1 => $value1, ... ) >>

Adds key => value pairs to the statistics for $category, timestamped with the
current date and time. Category and keys are strings, values are positive
integers.

=cut

sub add {
    my ( $class, $catkey, @stats ) = @_;
    my $catkey_id = $class->to_id( $catkey )
        or return undef;

    my $dbh = LJ::get_db_writer()
        or return undef;

    while ( my ( $key, $val ) = splice( @stats, 0, 2 ) ) {
        my $key_id = $class->to_id( $key )
            or next;

        # if this insert fails there's not much we can do about it, missing
        # statistics is not the end of the world
        $dbh->do(
            q{INSERT INTO site_stats (category_id, key_id, insert_time, value)
              VALUES (?, ?, UNIX_TIMESTAMP(), ?)},
            undef, $catkey_id, $key_id, $val+0
        );
    }

    return 1;
}

=head2 C<< $class->to_id( $key ) >>

Internal: converts key to an id. Key can be either a cat key or a stat key.
Autocreated on first reference.

=cut

sub to_id {
    return $_[0]->typemap->class_to_typeid( $_[1] );
}

=head2 C<< $class->typemap >>

Internal: returns typemap for storing cat keys and stat keys. Autovivified.

=cut

my $tm;
sub typemap {
    $tm ||= LJ::Typemap->new( table => 'statkeylist',
                              classfield => 'name',
                              idfield => 'statkeyid' );
    return $tm;
}

1;

=head1 BUGS

There's no API for retrieving stat data.

=head1 AUTHORS

Mark Smith <mark@dreamwidth.org>

Pau Amma <pauamma@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.
