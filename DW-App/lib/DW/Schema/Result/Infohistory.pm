use utf8;
package DW::Schema::Result::Infohistory;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Infohistory

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

=head1 TABLE: C<infohistory>

=cut

__PACKAGE__->table("infohistory");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 what

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 15

=head2 timechange

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  default_value: 'CURRENT_TIMESTAMP'
  is_nullable: 0

=head2 oldvalue

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 other

  data_type: 'varchar'
  is_nullable: 1
  size: 30

=cut

__PACKAGE__->add_columns(
  "userid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "what",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 15 },
  "timechange",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    default_value => "CURRENT_TIMESTAMP",
    is_nullable => 0,
  },
  "oldvalue",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "other",
  { data_type => "varchar", is_nullable => 1, size => 30 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:bg226Kw6UN9U5jVl1Kj+Fg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
