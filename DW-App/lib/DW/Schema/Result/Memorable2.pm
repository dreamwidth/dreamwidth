use utf8;
package DW::Schema::Result::Memorable2;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Memorable2

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

=head1 TABLE: C<memorable2>

=cut

__PACKAGE__->table("memorable2");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 memid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 journalid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 ditemid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 des

  data_type: 'varchar'
  is_nullable: 1
  size: 150

=head2 security

  data_type: 'enum'
  default_value: 'public'
  extra: {list => ["public","friends","private"]}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "userid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "memid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "journalid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "ditemid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "des",
  { data_type => "varchar", is_nullable => 1, size => 150 },
  "security",
  {
    data_type => "enum",
    default_value => "public",
    extra => { list => ["public", "friends", "private"] },
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=item * L</journalid>

=item * L</ditemid>

=back

=cut

__PACKAGE__->set_primary_key("userid", "journalid", "ditemid");

=head1 UNIQUE CONSTRAINTS

=head2 C<userid>

=over 4

=item * L</userid>

=item * L</memid>

=back

=cut

__PACKAGE__->add_unique_constraint("userid", ["userid", "memid"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:cA7ZzmtuC6msbWXfDX1CxQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
