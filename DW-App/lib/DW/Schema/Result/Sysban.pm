use utf8;
package DW::Schema::Result::Sysban;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Sysban

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

=head1 TABLE: C<sysban>

=cut

__PACKAGE__->table("sysban");

=head1 ACCESSORS

=head2 banid

  data_type: 'mediumint'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 status

  data_type: 'enum'
  default_value: 'active'
  extra: {list => ["active","expired"]}
  is_nullable: 0

=head2 bandate

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 banuntil

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 what

  data_type: 'varchar'
  is_nullable: 0
  size: 20

=head2 value

  data_type: 'varchar'
  is_nullable: 1
  size: 80

=head2 note

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
  "banid",
  {
    data_type => "mediumint",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "status",
  {
    data_type => "enum",
    default_value => "active",
    extra => { list => ["active", "expired"] },
    is_nullable => 0,
  },
  "bandate",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "banuntil",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "what",
  { data_type => "varchar", is_nullable => 0, size => 20 },
  "value",
  { data_type => "varchar", is_nullable => 1, size => 80 },
  "note",
  { data_type => "varchar", is_nullable => 1, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</banid>

=back

=cut

__PACKAGE__->set_primary_key("banid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:s3JKxyNiSX3P5cT15K0M1g


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
