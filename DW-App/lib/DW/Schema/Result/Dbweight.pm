use utf8;
package DW::Schema::Result::Dbweight;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Dbweight

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

=head1 TABLE: C<dbweights>

=cut

__PACKAGE__->table("dbweights");

=head1 ACCESSORS

=head2 dbid

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 role

  data_type: 'varchar'
  is_nullable: 0
  size: 25

=head2 norm

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 curr

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "dbid",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "role",
  { data_type => "varchar", is_nullable => 0, size => 25 },
  "norm",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "curr",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</dbid>

=item * L</role>

=back

=cut

__PACKAGE__->set_primary_key("dbid", "role");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:IsJ3eEyVRrcUfNQL9AZ9PA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
