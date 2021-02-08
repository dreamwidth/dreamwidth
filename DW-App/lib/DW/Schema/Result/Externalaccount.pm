use utf8;
package DW::Schema::Result::Externalaccount;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Externalaccount

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

=head1 TABLE: C<externalaccount>

=cut

__PACKAGE__->table("externalaccount");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 acctid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 username

  data_type: 'varchar'
  is_nullable: 0
  size: 64

=head2 password

  data_type: 'varchar'
  is_nullable: 1
  size: 64

=head2 siteid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 servicename

  data_type: 'varchar'
  is_nullable: 1
  size: 128

=head2 servicetype

  data_type: 'varchar'
  is_nullable: 1
  size: 32

=head2 serviceurl

  data_type: 'varchar'
  is_nullable: 1
  size: 128

=head2 xpostbydefault

  data_type: 'enum'
  default_value: 0
  extra: {list => [1,0]}
  is_nullable: 0

=head2 recordlink

  data_type: 'enum'
  default_value: 0
  extra: {list => [1,0]}
  is_nullable: 0

=head2 active

  data_type: 'enum'
  default_value: 1
  extra: {list => [1,0]}
  is_nullable: 0

=head2 options

  data_type: 'blob'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "acctid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "username",
  { data_type => "varchar", is_nullable => 0, size => 64 },
  "password",
  { data_type => "varchar", is_nullable => 1, size => 64 },
  "siteid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "servicename",
  { data_type => "varchar", is_nullable => 1, size => 128 },
  "servicetype",
  { data_type => "varchar", is_nullable => 1, size => 32 },
  "serviceurl",
  { data_type => "varchar", is_nullable => 1, size => 128 },
  "xpostbydefault",
  {
    data_type => "enum",
    default_value => 0,
    extra => { list => [1, 0] },
    is_nullable => 0,
  },
  "recordlink",
  {
    data_type => "enum",
    default_value => 0,
    extra => { list => [1, 0] },
    is_nullable => 0,
  },
  "active",
  {
    data_type => "enum",
    default_value => 1,
    extra => { list => [1, 0] },
    is_nullable => 0,
  },
  "options",
  { data_type => "blob", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=item * L</acctid>

=back

=cut

__PACKAGE__->set_primary_key("userid", "acctid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:1ik7hKKpJigFZtzCo2CwcQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
