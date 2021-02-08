use utf8;
package DW::Schema::Result::TrustGroup;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::TrustGroup

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

=head1 TABLE: C<trust_groups>

=cut

__PACKAGE__->table("trust_groups");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 groupnum

  data_type: 'tinyint'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 groupname

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 90

=head2 sortorder

  data_type: 'tinyint'
  default_value: 50
  extra: {unsigned => 1}
  is_nullable: 0

=head2 is_public

  data_type: 'enum'
  default_value: 0
  extra: {list => [0,1]}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "userid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "groupnum",
  {
    data_type => "tinyint",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "groupname",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 90 },
  "sortorder",
  {
    data_type => "tinyint",
    default_value => 50,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "is_public",
  {
    data_type => "enum",
    default_value => 0,
    extra => { list => [0, 1] },
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=item * L</groupnum>

=back

=cut

__PACKAGE__->set_primary_key("userid", "groupnum");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:7mFyyx+6v6owpGWgwArz9Q


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
