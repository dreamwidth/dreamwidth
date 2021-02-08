use utf8;
package DW::Schema::Result::MlDomain;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::MlDomain

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

=head1 TABLE: C<ml_domains>

=cut

__PACKAGE__->table("ml_domains");

=head1 ACCESSORS

=head2 dmid

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 type

  data_type: 'varchar'
  is_nullable: 0
  size: 30

=head2 args

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 255

=cut

__PACKAGE__->add_columns(
  "dmid",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "type",
  { data_type => "varchar", is_nullable => 0, size => 30 },
  "args",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</dmid>

=back

=cut

__PACKAGE__->set_primary_key("dmid");

=head1 UNIQUE CONSTRAINTS

=head2 C<type>

=over 4

=item * L</type>

=item * L</args>

=back

=cut

__PACKAGE__->add_unique_constraint("type", ["type", "args"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:IVcofD0VpxIImctgUksJpA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
