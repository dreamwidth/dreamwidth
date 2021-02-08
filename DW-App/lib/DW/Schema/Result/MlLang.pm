use utf8;
package DW::Schema::Result::MlLang;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::MlLang

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

=head1 TABLE: C<ml_langs>

=cut

__PACKAGE__->table("ml_langs");

=head1 ACCESSORS

=head2 lnid

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 lncode

  data_type: 'varchar'
  is_nullable: 0
  size: 16

=head2 lnname

  data_type: 'varchar'
  is_nullable: 0
  size: 60

=head2 parenttype

  data_type: 'enum'
  extra: {list => ["diff","sim"]}
  is_nullable: 0

=head2 parentlnid

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 lastupdate

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  default_value: 'CURRENT_TIMESTAMP'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "lnid",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
  "lncode",
  { data_type => "varchar", is_nullable => 0, size => 16 },
  "lnname",
  { data_type => "varchar", is_nullable => 0, size => 60 },
  "parenttype",
  {
    data_type => "enum",
    extra => { list => ["diff", "sim"] },
    is_nullable => 0,
  },
  "parentlnid",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
  "lastupdate",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    default_value => "CURRENT_TIMESTAMP",
    is_nullable => 0,
  },
);

=head1 UNIQUE CONSTRAINTS

=head2 C<lncode>

=over 4

=item * L</lncode>

=back

=cut

__PACKAGE__->add_unique_constraint("lncode", ["lncode"]);

=head2 C<lnid>

=over 4

=item * L</lnid>

=back

=cut

__PACKAGE__->add_unique_constraint("lnid", ["lnid"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:GwpMfRrBIp/+F7D0Sn9NZA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
