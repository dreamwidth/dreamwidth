use utf8;
package DW::Schema::Result::Userproplist;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Userproplist

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

=head1 TABLE: C<userproplist>

=cut

__PACKAGE__->table("userproplist");

=head1 ACCESSORS

=head2 upropid

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 1
  size: 50

=head2 indexed

  data_type: 'enum'
  default_value: 1
  extra: {list => [1,0]}
  is_nullable: 0

=head2 cldversion

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 multihomed

  data_type: 'enum'
  default_value: 0
  extra: {list => [1,0]}
  is_nullable: 0

=head2 prettyname

  data_type: 'varchar'
  is_nullable: 1
  size: 60

=head2 datatype

  data_type: 'enum'
  default_value: 'char'
  extra: {list => ["char","num","bool","blobchar"]}
  is_nullable: 0

=head2 des

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 scope

  data_type: 'enum'
  default_value: 'general'
  extra: {list => ["general","local"]}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "upropid",
  {
    data_type => "smallint",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "name",
  { data_type => "varchar", is_nullable => 1, size => 50 },
  "indexed",
  {
    data_type => "enum",
    default_value => 1,
    extra => { list => [1, 0] },
    is_nullable => 0,
  },
  "cldversion",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "multihomed",
  {
    data_type => "enum",
    default_value => 0,
    extra => { list => [1, 0] },
    is_nullable => 0,
  },
  "prettyname",
  { data_type => "varchar", is_nullable => 1, size => 60 },
  "datatype",
  {
    data_type => "enum",
    default_value => "char",
    extra => { list => ["char", "num", "bool", "blobchar"] },
    is_nullable => 0,
  },
  "des",
  { data_type => "varchar", is_nullable => 1, size => 255 },
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

=item * L</upropid>

=back

=cut

__PACKAGE__->set_primary_key("upropid");

=head1 UNIQUE CONSTRAINTS

=head2 C<name>

=over 4

=item * L</name>

=back

=cut

__PACKAGE__->add_unique_constraint("name", ["name"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:JBv3PzMf4/FCGC9+CAyBlQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
