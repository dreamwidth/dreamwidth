use utf8;
package DW::Schema::Result::Usermsgproplist;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Usermsgproplist

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

=head1 TABLE: C<usermsgproplist>

=cut

__PACKAGE__->table("usermsgproplist");

=head1 ACCESSORS

=head2 propid

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 1
  size: 255

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
  "propid",
  {
    data_type => "smallint",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "name",
  { data_type => "varchar", is_nullable => 1, size => 255 },
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

=item * L</propid>

=back

=cut

__PACKAGE__->set_primary_key("propid");

=head1 UNIQUE CONSTRAINTS

=head2 C<name>

=over 4

=item * L</name>

=back

=cut

__PACKAGE__->add_unique_constraint("name", ["name"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:fOE12HviTPpz0iTK4pBMSg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
