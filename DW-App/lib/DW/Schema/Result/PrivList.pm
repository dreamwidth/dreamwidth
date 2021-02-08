use utf8;
package DW::Schema::Result::PrivList;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::PrivList

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

=head1 TABLE: C<priv_list>

=cut

__PACKAGE__->table("priv_list");

=head1 ACCESSORS

=head2 prlid

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 privcode

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 20

=head2 privname

  data_type: 'varchar'
  is_nullable: 1
  size: 40

=head2 des

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 is_public

  data_type: 'enum'
  default_value: 1
  extra: {list => [1,0]}
  is_nullable: 0

=head2 scope

  data_type: 'enum'
  default_value: 'general'
  extra: {list => ["general","local"]}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "prlid",
  {
    data_type => "smallint",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "privcode",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 20 },
  "privname",
  { data_type => "varchar", is_nullable => 1, size => 40 },
  "des",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "is_public",
  {
    data_type => "enum",
    default_value => 1,
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

=item * L</prlid>

=back

=cut

__PACKAGE__->set_primary_key("prlid");

=head1 UNIQUE CONSTRAINTS

=head2 C<privcode>

=over 4

=item * L</privcode>

=back

=cut

__PACKAGE__->add_unique_constraint("privcode", ["privcode"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:1CPPeR0xvcq922Kx9yeBPA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
