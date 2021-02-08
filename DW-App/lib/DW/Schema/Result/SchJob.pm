use utf8;
package DW::Schema::Result::SchJob;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::SchJob

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

=head1 TABLE: C<sch_job>

=cut

__PACKAGE__->table("sch_job");

=head1 ACCESSORS

=head2 jobid

  data_type: 'bigint'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 funcid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 arg

  data_type: 'mediumblob'
  is_nullable: 1

=head2 uniqkey

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 insert_time

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 run_after

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 grabbed_until

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 priority

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 coalesce

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
  "jobid",
  {
    data_type => "bigint",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "funcid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "arg",
  { data_type => "mediumblob", is_nullable => 1 },
  "uniqkey",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "insert_time",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "run_after",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "grabbed_until",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "priority",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 1 },
  "coalesce",
  { data_type => "varchar", is_nullable => 1, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</jobid>

=back

=cut

__PACKAGE__->set_primary_key("jobid");

=head1 UNIQUE CONSTRAINTS

=head2 C<funcid_2>

=over 4

=item * L</funcid>

=item * L</uniqkey>

=back

=cut

__PACKAGE__->add_unique_constraint("funcid_2", ["funcid", "uniqkey"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:wnqTMhWPPkCI5DRAaxGZrQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
