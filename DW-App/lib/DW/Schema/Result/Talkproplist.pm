use utf8;
package DW::Schema::Result::Talkproplist;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Talkproplist

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

=head1 TABLE: C<talkproplist>

=cut

__PACKAGE__->table("talkproplist");

=head1 ACCESSORS

=head2 tpropid

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 1
  size: 50

=head2 prettyname

  data_type: 'varchar'
  is_nullable: 1
  size: 60

=head2 datatype

  data_type: 'enum'
  default_value: 'char'
  extra: {list => ["char","num","bool","blobchar"]}
  is_nullable: 0

=head2 scope

  data_type: 'enum'
  default_value: 'general'
  extra: {list => ["general","local"]}
  is_nullable: 0

=head2 ownership

  data_type: 'enum'
  default_value: 'user'
  extra: {list => ["system","user"]}
  is_nullable: 0

=head2 des

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
  "tpropid",
  {
    data_type => "smallint",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "name",
  { data_type => "varchar", is_nullable => 1, size => 50 },
  "prettyname",
  { data_type => "varchar", is_nullable => 1, size => 60 },
  "datatype",
  {
    data_type => "enum",
    default_value => "char",
    extra => { list => ["char", "num", "bool", "blobchar"] },
    is_nullable => 0,
  },
  "scope",
  {
    data_type => "enum",
    default_value => "general",
    extra => { list => ["general", "local"] },
    is_nullable => 0,
  },
  "ownership",
  {
    data_type => "enum",
    default_value => "user",
    extra => { list => ["system", "user"] },
    is_nullable => 0,
  },
  "des",
  { data_type => "varchar", is_nullable => 1, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</tpropid>

=back

=cut

__PACKAGE__->set_primary_key("tpropid");

=head1 UNIQUE CONSTRAINTS

=head2 C<name>

=over 4

=item * L</name>

=back

=cut

__PACKAGE__->add_unique_constraint("name", ["name"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:IByfKxFgtHWCq7m9b9gPcA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
