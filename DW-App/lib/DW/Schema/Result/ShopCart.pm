use utf8;
package DW::Schema::Result::ShopCart;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::ShopCart

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

=head1 TABLE: C<shop_carts>

=cut

__PACKAGE__->table("shop_carts");

=head1 ACCESSORS

=head2 cartid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 starttime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 email

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 uniq

  data_type: 'varchar'
  is_nullable: 0
  size: 15

=head2 state

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 paymentmethod

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 nextscan

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 authcode

  data_type: 'varchar'
  is_nullable: 0
  size: 20

=head2 cartblob

  data_type: 'mediumblob'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "cartid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "starttime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "email",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "uniq",
  { data_type => "varchar", is_nullable => 0, size => 15 },
  "state",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "paymentmethod",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "nextscan",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "authcode",
  { data_type => "varchar", is_nullable => 0, size => 20 },
  "cartblob",
  { data_type => "mediumblob", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</cartid>

=back

=cut

__PACKAGE__->set_primary_key("cartid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:MEvLzQlW6L4DvFF84cYBng


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
