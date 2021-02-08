use utf8;
package DW::Schema::Result::Log2;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Log2

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

=head1 TABLE: C<log2>

=cut

__PACKAGE__->table("log2");

=head1 ACCESSORS

=head2 journalid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 jitemid

  data_type: 'mediumint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 posterid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 eventtime

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 logtime

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 compressed

  data_type: 'char'
  default_value: 'N'
  is_nullable: 0
  size: 1

=head2 anum

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 security

  data_type: 'enum'
  default_value: 'public'
  extra: {list => ["public","private","usemask"]}
  is_nullable: 0

=head2 allowmask

  data_type: 'bigint'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 replycount

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 year

  data_type: 'smallint'
  default_value: 0
  is_nullable: 0

=head2 month

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=head2 day

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=head2 rlogtime

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 revttime

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "journalid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "jitemid",
  { data_type => "mediumint", extra => { unsigned => 1 }, is_nullable => 0 },
  "posterid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "eventtime",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "logtime",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "compressed",
  { data_type => "char", default_value => "N", is_nullable => 0, size => 1 },
  "anum",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "security",
  {
    data_type => "enum",
    default_value => "public",
    extra => { list => ["public", "private", "usemask"] },
    is_nullable => 0,
  },
  "allowmask",
  {
    data_type => "bigint",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "replycount",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 1 },
  "year",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "month",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
  "day",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
  "rlogtime",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "revttime",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</journalid>

=item * L</jitemid>

=back

=cut

__PACKAGE__->set_primary_key("journalid", "jitemid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:dulIHrp3T7x9+ZxO8FJMeg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
