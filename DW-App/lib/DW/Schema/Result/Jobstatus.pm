use utf8;
package DW::Schema::Result::Jobstatus;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Jobstatus

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

=head1 TABLE: C<jobstatus>

=cut

__PACKAGE__->table("jobstatus");

=head1 ACCESSORS

=head2 handle

  data_type: 'varchar'
  is_nullable: 0
  size: 100

=head2 result

  data_type: 'blob'
  is_nullable: 1

=head2 start_time

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 end_time

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 status

  data_type: 'enum'
  extra: {list => ["running","success","error"]}
  is_nullable: 1

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "handle",
  { data_type => "varchar", is_nullable => 0, size => 100 },
  "result",
  { data_type => "blob", is_nullable => 1 },
  "start_time",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "end_time",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "status",
  {
    data_type => "enum",
    extra => { list => ["running", "success", "error"] },
    is_nullable => 1,
  },
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</handle>

=back

=cut

__PACKAGE__->set_primary_key("handle");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:WSrz1xF+JAOZp1oZIonaew


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
