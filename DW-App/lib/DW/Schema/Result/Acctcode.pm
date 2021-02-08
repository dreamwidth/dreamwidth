use utf8;
package DW::Schema::Result::Acctcode;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Acctcode

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

=head1 TABLE: C<acctcode>

=cut

__PACKAGE__->table("acctcode");

=head1 ACCESSORS

=head2 acid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 rcptid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 auth

  data_type: 'char'
  is_nullable: 0
  size: 13

=head2 timegenerate

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 timesent

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 email

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 reason

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
  "acid",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "rcptid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "auth",
  { data_type => "char", is_nullable => 0, size => 13 },
  "timegenerate",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "timesent",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "email",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "reason",
  { data_type => "varchar", is_nullable => 1, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</acid>

=back

=cut

__PACKAGE__->set_primary_key("acid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:FpNgJS4EC5Wjn+eIy/fJiw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
