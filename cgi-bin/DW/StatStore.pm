#!/usr/bin/perl
#
# DW::StatStore
#
# Used for storing, loading, inserting, updating, etc stats.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Pau Amma <pauamma@dreamwidth.org>
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009-2010 by Dreamwidth Studios, LLC.
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

  # get pony stats from one day ago
  DW::StatStore->get( 'ponies' );

  # get pony stats over the last 30 days
  DW::StatStore->get( 'ponies', 30 );

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
    my $catkey_id = $class->to_id($catkey)
        or return undef;

    my $dbh = LJ::get_db_writer()
        or return undef;

    # Using UNIX_TIMESTAMP can cause partial retrievals in get_latest if the
    # database server clock ticks between keys for the category.
    my $now = time;

    while ( my ( $key, $val ) = splice( @stats, 0, 2 ) ) {
        my $key_id = $class->to_id($key)
            or next;

        # if this insert fails there's not much we can do about it, missing
        # statistics is not the end of the world
        $dbh->do(
            q{INSERT INTO site_stats (category_id, key_id, insert_time, value)
              VALUES (?, ?, ?, ?)},
            undef, $catkey_id, $key_id, $now, $val + 0
        );
    }

    return 1;
}

=head2 C<< $class->get( $catkey, $statkeys, $howmany ) >>

Get statistics data over the past $numdays for all keys under this category. Catkey is a string. $numdays defaults to 1.

=cut

sub get {
    my ( $class, $catkey, $numdays ) = @_;

    my $catkey_id = $class->to_id($catkey);
    return undef unless $catkey_id;

    $numdays ||= 1;
    my $timestamp = time() - $numdays * 24 * 60 * 60;

    my $dbr = LJ::get_db_reader()
        or return undef;

    my $sth =
        $dbr->prepare( "SELECT category_id, key_id, insert_time, value "
            . "FROM site_stats "
            . "WHERE category_id = ? AND insert_time >= ? " );
    $sth->execute( $catkey_id, $timestamp );

    my %ret;
    while ( my $data = $sth->fetchrow_hashref ) {
        my $key = $class->to_key( $data->{key_id} )
            or next;

        $ret{ $data->{insert_time} }->{$key} = $data->{value};
    }
    return \%ret;
}

=head2 C<< $class->to_id( $key ) >>

Internal: converts key to an id. Key can be either a cat key or a stat key.
Autocreated on first reference.

=cut

sub to_id {
    return $_[0]->typemap->class_to_typeid( $_[1] );
}

=head2 C<< $class->to_key( $id ) >>

Internal: converts id to a key. Errors hard if you give an invalid id.

=cut

sub to_key {
    return $_[0]->typemap->typeid_to_class( $_[1] );
}

=head2 C<< $class->typemap >>

Internal: returns typemap for storing cat keys and stat keys. Autovivified.

=cut

my $tm;

sub typemap {
    $tm ||= LJ::Typemap->new(
        table      => 'statkeylist',
        classfield => 'name',
        idfield    => 'statkeyid'
    );
    return $tm;
}

1;

=head1 BUGS

=head1 AUTHORS

Mark Smith <mark@dreamwidth.org>

Pau Amma <pauamma@dreamwidth.org>

Afuna <coder.dw@afunamatata.com>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.
