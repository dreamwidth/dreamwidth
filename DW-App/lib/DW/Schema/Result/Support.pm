use utf8;
package DW::Schema::Result::Support;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Support

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

=head1 TABLE: C<support>

=cut

__PACKAGE__->table("support");

=head1 ACCESSORS

=head2 spid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 reqtype

  data_type: 'enum'
  extra: {list => ["user","email"]}
  is_nullable: 1

=head2 requserid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 reqname

  data_type: 'varchar'
  is_nullable: 1
  size: 50

=head2 reqemail

  data_type: 'varchar'
  is_nullable: 1
  size: 70

=head2 state

  data_type: 'enum'
  extra: {list => ["open","closed"]}
  is_nullable: 1

=head2 authcode

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 15

=head2 spcatid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 subject

  data_type: 'varchar'
  is_nullable: 1
  size: 80

=head2 timecreate

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 timetouched

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 timemodified

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 timeclosed

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 timelasthelp

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "spid",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "reqtype",
  {
    data_type => "enum",
    extra => { list => ["user", "email"] },
    is_nullable => 1,
  },
  "requserid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "reqname",
  { data_type => "varchar", is_nullable => 1, size => 50 },
  "reqemail",
  { data_type => "varchar", is_nullable => 1, size => 70 },
  "state",
  {
    data_type => "enum",
    extra => { list => ["open", "closed"] },
    is_nullable => 1,
  },
  "authcode",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 15 },
  "spcatid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "subject",
  { data_type => "varchar", is_nullable => 1, size => 80 },
  "timecreate",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "timetouched",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "timemodified",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "timeclosed",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "timelasthelp",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</spid>

=back

=cut

__PACKAGE__->set_primary_key("spid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:+c9348+AIS4ZCXa0DrSEpg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
