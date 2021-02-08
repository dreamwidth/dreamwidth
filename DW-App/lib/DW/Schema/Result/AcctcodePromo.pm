use utf8;
package DW::Schema::Result::AcctcodePromo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::AcctcodePromo

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

=head1 TABLE: C<acctcode_promo>

=cut

__PACKAGE__->table("acctcode_promo");

=head1 ACCESSORS

=head2 code

  data_type: 'varchar'
  is_nullable: 0
  size: 20

=head2 max_count

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 current_count

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 active

  data_type: 'enum'
  default_value: 1
  extra: {list => [1,0]}
  is_nullable: 0

=head2 suggest_journalid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 paid_class

  data_type: 'varchar'
  is_nullable: 1
  size: 100

=head2 paid_months

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 expiry_date

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "code",
  { data_type => "varchar", is_nullable => 0, size => 20 },
  "max_count",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "current_count",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "active",
  {
    data_type => "enum",
    default_value => 1,
    extra => { list => [1, 0] },
    is_nullable => 0,
  },
  "suggest_journalid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "paid_class",
  { data_type => "varchar", is_nullable => 1, size => 100 },
  "paid_months",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 1 },
  "expiry_date",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</code>

=back

=cut

__PACKAGE__->set_primary_key("code");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:eDNMlIXo69UidJ52ccwOSw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
