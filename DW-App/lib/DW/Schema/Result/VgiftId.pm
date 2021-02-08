use utf8;
package DW::Schema::Result::VgiftId;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::VgiftId

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

=head1 TABLE: C<vgift_ids>

=cut

__PACKAGE__->table("vgift_ids");

=head1 ACCESSORS

=head2 vgiftid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 created_t

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 creatorid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 active

  data_type: 'enum'
  default_value: 'N'
  extra: {list => ["Y","N"]}
  is_nullable: 0

=head2 featured

  data_type: 'enum'
  default_value: 'N'
  extra: {list => ["Y","N"]}
  is_nullable: 0

=head2 custom

  data_type: 'enum'
  default_value: 'N'
  extra: {list => ["Y","N"]}
  is_nullable: 0

=head2 approved

  data_type: 'enum'
  extra: {list => ["Y","N"]}
  is_nullable: 1

=head2 approved_by

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 approved_why

  data_type: 'mediumtext'
  is_nullable: 1

=head2 description

  data_type: 'mediumtext'
  is_nullable: 1

=head2 cost

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 mime_small

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 mime_large

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
  "vgiftid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "name",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "created_t",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "creatorid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "active",
  {
    data_type => "enum",
    default_value => "N",
    extra => { list => ["Y", "N"] },
    is_nullable => 0,
  },
  "featured",
  {
    data_type => "enum",
    default_value => "N",
    extra => { list => ["Y", "N"] },
    is_nullable => 0,
  },
  "custom",
  {
    data_type => "enum",
    default_value => "N",
    extra => { list => ["Y", "N"] },
    is_nullable => 0,
  },
  "approved",
  { data_type => "enum", extra => { list => ["Y", "N"] }, is_nullable => 1 },
  "approved_by",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "approved_why",
  { data_type => "mediumtext", is_nullable => 1 },
  "description",
  { data_type => "mediumtext", is_nullable => 1 },
  "cost",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "mime_small",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "mime_large",
  { data_type => "varchar", is_nullable => 1, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</vgiftid>

=back

=cut

__PACKAGE__->set_primary_key("vgiftid");

=head1 UNIQUE CONSTRAINTS

=head2 C<name>

=over 4

=item * L</name>

=back

=cut

__PACKAGE__->add_unique_constraint("name", ["name"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:eD8KSom8bzXwwOXtbpf3Zw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
