use utf8;
package DW::Schema::Result::GcoMap;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::GcoMap

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

=head1 TABLE: C<gco_map>

=cut

__PACKAGE__->table("gco_map");

=head1 ACCESSORS

=head2 gcoid

  data_type: 'bigint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 cartid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 email

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 contactname

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
  "gcoid",
  { data_type => "bigint", extra => { unsigned => 1 }, is_nullable => 0 },
  "cartid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "email",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "contactname",
  { data_type => "varchar", is_nullable => 1, size => 255 },
);

=head1 UNIQUE CONSTRAINTS

=head2 C<cartid>

=over 4

=item * L</cartid>

=back

=cut

__PACKAGE__->add_unique_constraint("cartid", ["cartid"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:54CGM3gBit/IxbAvu7RNvA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
