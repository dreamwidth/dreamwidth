use utf8;
package DW::Schema::Result::MlItem;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::MlItem

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

=head1 TABLE: C<ml_items>

=cut

__PACKAGE__->table("ml_items");

=head1 ACCESSORS

=head2 dmid

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 itid

  data_type: 'mediumint'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 itcode

  data_type: 'varchar'
  is_nullable: 0
  size: 120

=head2 proofed

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=head2 updated

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=head2 visible

  data_type: 'tinyint'
  default_value: 0
  is_nullable: 0

=head2 notes

  data_type: 'mediumtext'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "dmid",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "itid",
  {
    data_type => "mediumint",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "itcode",
  { data_type => "varchar", is_nullable => 0, size => 120 },
  "proofed",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
  "updated",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
  "visible",
  { data_type => "tinyint", default_value => 0, is_nullable => 0 },
  "notes",
  { data_type => "mediumtext", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</dmid>

=item * L</itid>

=back

=cut

__PACKAGE__->set_primary_key("dmid", "itid");

=head1 UNIQUE CONSTRAINTS

=head2 C<dmid>

=over 4

=item * L</dmid>

=item * L</itcode>

=back

=cut

__PACKAGE__->add_unique_constraint("dmid", ["dmid", "itcode"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:aOAGSEG/fzNAssrbJOPgAA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
