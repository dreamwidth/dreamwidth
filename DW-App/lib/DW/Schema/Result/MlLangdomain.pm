use utf8;
package DW::Schema::Result::MlLangdomain;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::MlLangdomain

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

=head1 TABLE: C<ml_langdomains>

=cut

__PACKAGE__->table("ml_langdomains");

=head1 ACCESSORS

=head2 lnid

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 dmid

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 dmmaster

  data_type: 'enum'
  extra: {list => [0,1]}
  is_nullable: 0

=head2 lastgetnew

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 lastpublish

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 countokay

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 counttotal

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "lnid",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
  "dmid",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "dmmaster",
  { data_type => "enum", extra => { list => [0, 1] }, is_nullable => 0 },
  "lastgetnew",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "lastpublish",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "countokay",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
  "counttotal",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</lnid>

=item * L</dmid>

=back

=cut

__PACKAGE__->set_primary_key("lnid", "dmid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ABiYExfqv4bonBumR+G86g


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
