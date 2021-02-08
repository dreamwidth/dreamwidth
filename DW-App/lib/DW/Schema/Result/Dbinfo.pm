use utf8;
package DW::Schema::Result::Dbinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Dbinfo

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 TABLE: C<dbinfo>

=cut

__PACKAGE__->table("dbinfo");

=head1 ACCESSORS

=head2 dbid

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 1
  size: 25

=head2 fdsn

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 rootfdsn

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 masterid

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "dbid",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "name",
  { data_type => "varchar", is_nullable => 1, size => 25 },
  "fdsn",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "rootfdsn",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "masterid",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</dbid>

=back

=cut

__PACKAGE__->set_primary_key("dbid");

=head1 UNIQUE CONSTRAINTS

=head2 C<name>

=over 4

=item * L</name>

=back

=cut

__PACKAGE__->add_unique_constraint("name", ["name"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:OPSwnkFvP8x6gb+5+NOGQQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
