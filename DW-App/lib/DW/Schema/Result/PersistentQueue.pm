use utf8;
package DW::Schema::Result::PersistentQueue;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::PersistentQueue

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

=head1 TABLE: C<persistent_queue>

=cut

__PACKAGE__->table("persistent_queue");

=head1 ACCESSORS

=head2 qkey

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 idx

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 value

  data_type: 'blob'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "qkey",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "idx",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "value",
  { data_type => "blob", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</qkey>

=item * L</idx>

=back

=cut

__PACKAGE__->set_primary_key("qkey", "idx");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:3+ZFzf68nF75IFwbAEo3YQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
