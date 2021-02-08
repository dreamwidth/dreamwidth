use utf8;
package DW::Schema::Result::Supportcat;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Supportcat

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

=head1 TABLE: C<supportcat>

=cut

__PACKAGE__->table("supportcat");

=head1 ACCESSORS

=head2 spcatid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 catkey

  data_type: 'varchar'
  is_nullable: 0
  size: 25

=head2 catname

  data_type: 'varchar'
  is_nullable: 1
  size: 80

=head2 sortorder

  data_type: 'mediumint'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 basepoints

  data_type: 'tinyint'
  default_value: 1
  extra: {unsigned => 1}
  is_nullable: 0

=head2 is_selectable

  data_type: 'enum'
  default_value: 1
  extra: {list => [1,0]}
  is_nullable: 0

=head2 public_read

  data_type: 'enum'
  default_value: 1
  extra: {list => [1,0]}
  is_nullable: 0

=head2 public_help

  data_type: 'enum'
  default_value: 1
  extra: {list => [1,0]}
  is_nullable: 0

=head2 allow_screened

  data_type: 'enum'
  default_value: 0
  extra: {list => [1,0]}
  is_nullable: 0

=head2 hide_helpers

  data_type: 'enum'
  default_value: 0
  extra: {list => [1,0]}
  is_nullable: 0

=head2 user_closeable

  data_type: 'enum'
  default_value: 1
  extra: {list => [1,0]}
  is_nullable: 0

=head2 replyaddress

  data_type: 'varchar'
  is_nullable: 1
  size: 50

=head2 no_autoreply

  data_type: 'enum'
  default_value: 0
  extra: {list => [1,0]}
  is_nullable: 0

=head2 scope

  data_type: 'enum'
  default_value: 'general'
  extra: {list => ["general","local"]}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "spcatid",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "catkey",
  { data_type => "varchar", is_nullable => 0, size => 25 },
  "catname",
  { data_type => "varchar", is_nullable => 1, size => 80 },
  "sortorder",
  {
    data_type => "mediumint",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "basepoints",
  {
    data_type => "tinyint",
    default_value => 1,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "is_selectable",
  {
    data_type => "enum",
    default_value => 1,
    extra => { list => [1, 0] },
    is_nullable => 0,
  },
  "public_read",
  {
    data_type => "enum",
    default_value => 1,
    extra => { list => [1, 0] },
    is_nullable => 0,
  },
  "public_help",
  {
    data_type => "enum",
    default_value => 1,
    extra => { list => [1, 0] },
    is_nullable => 0,
  },
  "allow_screened",
  {
    data_type => "enum",
    default_value => 0,
    extra => { list => [1, 0] },
    is_nullable => 0,
  },
  "hide_helpers",
  {
    data_type => "enum",
    default_value => 0,
    extra => { list => [1, 0] },
    is_nullable => 0,
  },
  "user_closeable",
  {
    data_type => "enum",
    default_value => 1,
    extra => { list => [1, 0] },
    is_nullable => 0,
  },
  "replyaddress",
  { data_type => "varchar", is_nullable => 1, size => 50 },
  "no_autoreply",
  {
    data_type => "enum",
    default_value => 0,
    extra => { list => [1, 0] },
    is_nullable => 0,
  },
  "scope",
  {
    data_type => "enum",
    default_value => "general",
    extra => { list => ["general", "local"] },
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</spcatid>

=back

=cut

__PACKAGE__->set_primary_key("spcatid");

=head1 UNIQUE CONSTRAINTS

=head2 C<catkey>

=over 4

=item * L</catkey>

=back

=cut

__PACKAGE__->add_unique_constraint("catkey", ["catkey"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:+/NhHrk+OPHdHVuBOe/+2A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
