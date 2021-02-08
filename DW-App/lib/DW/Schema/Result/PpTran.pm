use utf8;
package DW::Schema::Result::PpTran;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::PpTran

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

=head1 TABLE: C<pp_trans>

=cut

__PACKAGE__->table("pp_trans");

=head1 ACCESSORS

=head2 ppid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 cartid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 transactionid

  data_type: 'varchar'
  is_nullable: 1
  size: 19

=head2 transactiontype

  data_type: 'varchar'
  is_nullable: 1
  size: 15

=head2 paymenttype

  data_type: 'varchar'
  is_nullable: 1
  size: 7

=head2 ordertime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 amt

  data_type: 'decimal'
  is_nullable: 1
  size: [10,2]

=head2 currencycode

  data_type: 'varchar'
  is_nullable: 1
  size: 3

=head2 feeamt

  data_type: 'decimal'
  is_nullable: 1
  size: [10,2]

=head2 settleamt

  data_type: 'decimal'
  is_nullable: 1
  size: [10,2]

=head2 taxamt

  data_type: 'decimal'
  is_nullable: 1
  size: [10,2]

=head2 paymentstatus

  data_type: 'varchar'
  is_nullable: 1
  size: 20

=head2 pendingreason

  data_type: 'varchar'
  is_nullable: 1
  size: 20

=head2 reasoncode

  data_type: 'varchar'
  is_nullable: 1
  size: 20

=head2 ack

  data_type: 'varchar'
  is_nullable: 1
  size: 20

=head2 timestamp

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 build

  data_type: 'varchar'
  is_nullable: 1
  size: 20

=cut

__PACKAGE__->add_columns(
  "ppid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "cartid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "transactionid",
  { data_type => "varchar", is_nullable => 1, size => 19 },
  "transactiontype",
  { data_type => "varchar", is_nullable => 1, size => 15 },
  "paymenttype",
  { data_type => "varchar", is_nullable => 1, size => 7 },
  "ordertime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "amt",
  { data_type => "decimal", is_nullable => 1, size => [10, 2] },
  "currencycode",
  { data_type => "varchar", is_nullable => 1, size => 3 },
  "feeamt",
  { data_type => "decimal", is_nullable => 1, size => [10, 2] },
  "settleamt",
  { data_type => "decimal", is_nullable => 1, size => [10, 2] },
  "taxamt",
  { data_type => "decimal", is_nullable => 1, size => [10, 2] },
  "paymentstatus",
  { data_type => "varchar", is_nullable => 1, size => 20 },
  "pendingreason",
  { data_type => "varchar", is_nullable => 1, size => 20 },
  "reasoncode",
  { data_type => "varchar", is_nullable => 1, size => 20 },
  "ack",
  { data_type => "varchar", is_nullable => 1, size => 20 },
  "timestamp",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "build",
  { data_type => "varchar", is_nullable => 1, size => 20 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:HW1oYA+tGHG9kTGVow1vxA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
