use utf8;
package DW::Schema::Result::Userpic2;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Userpic2

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

=head1 TABLE: C<userpic2>

=cut

__PACKAGE__->table("userpic2");

=head1 ACCESSORS

=head2 picid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 userid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 fmt

  data_type: 'char'
  is_nullable: 1
  size: 1

=head2 width

  data_type: 'smallint'
  default_value: 0
  is_nullable: 0

=head2 height

  data_type: 'smallint'
  default_value: 0
  is_nullable: 0

=head2 state

  data_type: 'char'
  default_value: 'N'
  is_nullable: 0
  size: 1

=head2 picdate

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 md5base64

  data_type: 'char'
  default_value: (empty string)
  is_nullable: 0
  size: 22

=head2 comment

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 255

=head2 description

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 600

=head2 flags

  data_type: 'tinyint'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 location

  data_type: 'enum'
  extra: {list => ["blob","disk","mogile","blobstore"]}
  is_nullable: 1

=head2 url

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
  "picid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "userid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "fmt",
  { data_type => "char", is_nullable => 1, size => 1 },
  "width",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "height",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "state",
  { data_type => "char", default_value => "N", is_nullable => 0, size => 1 },
  "picdate",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "md5base64",
  { data_type => "char", default_value => "", is_nullable => 0, size => 22 },
  "comment",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 255 },
  "description",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 600 },
  "flags",
  {
    data_type => "tinyint",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "location",
  {
    data_type => "enum",
    extra => { list => ["blob", "disk", "mogile", "blobstore"] },
    is_nullable => 1,
  },
  "url",
  { data_type => "varchar", is_nullable => 1, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=item * L</picid>

=back

=cut

__PACKAGE__->set_primary_key("userid", "picid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:W3bSlKDTQt6AV8NmbkKoKA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
