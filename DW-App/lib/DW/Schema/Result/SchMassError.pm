use utf8;
package DW::Schema::Result::SchMassError;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::SchMassError

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

=head1 TABLE: C<sch_mass_error>

=cut

__PACKAGE__->table("sch_mass_error");

=head1 ACCESSORS

=head2 error_time

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 jobid

  data_type: 'bigint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 message

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=cut

__PACKAGE__->add_columns(
  "error_time",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "jobid",
  { data_type => "bigint", extra => { unsigned => 1 }, is_nullable => 0 },
  "message",
  { data_type => "varchar", is_nullable => 0, size => 255 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:nO+Oc1T5wpktP4V6PtG0AQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
