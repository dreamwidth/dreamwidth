use utf8;
package DW::Schema::Result::Authaction;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Authaction

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

=head1 TABLE: C<authactions>

=cut

__PACKAGE__->table("authactions");

=head1 ACCESSORS

=head2 aaid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 userid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 datecreate

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  default_value: 'CURRENT_TIMESTAMP'
  is_nullable: 0

=head2 authcode

  data_type: 'varchar'
  is_nullable: 1
  size: 20

=head2 action

  data_type: 'varchar'
  is_nullable: 1
  size: 50

=head2 arg1

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 used

  data_type: 'enum'
  default_value: 'N'
  extra: {list => ["Y","N"]}
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "aaid",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "userid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "datecreate",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    default_value => "CURRENT_TIMESTAMP",
    is_nullable => 0,
  },
  "authcode",
  { data_type => "varchar", is_nullable => 1, size => 20 },
  "action",
  { data_type => "varchar", is_nullable => 1, size => 50 },
  "arg1",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "used",
  {
    data_type => "enum",
    default_value => "N",
    extra => { list => ["Y", "N"] },
    is_nullable => 1,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</aaid>

=back

=cut

__PACKAGE__->set_primary_key("aaid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:HNT+LG5BSrIQDbubZaetQQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
