use utf8;
package DW::Schema::Result::Stat;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Stat

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

=head1 TABLE: C<stats>

=cut

__PACKAGE__->table("stats");

=head1 ACCESSORS

=head2 statcat

  data_type: 'varchar'
  is_nullable: 0
  size: 30

=head2 statkey

  data_type: 'varchar'
  is_nullable: 0
  size: 150

=head2 statval

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "statcat",
  { data_type => "varchar", is_nullable => 0, size => 30 },
  "statkey",
  { data_type => "varchar", is_nullable => 0, size => 150 },
  "statval",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
);

=head1 UNIQUE CONSTRAINTS

=head2 C<statcat_2>

=over 4

=item * L</statcat>

=item * L</statkey>

=back

=cut

__PACKAGE__->add_unique_constraint("statcat_2", ["statcat", "statkey"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:JZxT/lQQj3jI+V++keuJSA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
