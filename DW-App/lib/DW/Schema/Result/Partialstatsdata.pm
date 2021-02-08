use utf8;
package DW::Schema::Result::Partialstatsdata;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Partialstatsdata

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

=head1 TABLE: C<partialstatsdata>

=cut

__PACKAGE__->table("partialstatsdata");

=head1 ACCESSORS

=head2 statname

  data_type: 'varchar'
  is_nullable: 0
  size: 50

=head2 arg

  data_type: 'varchar'
  is_nullable: 0
  size: 50

=head2 clusterid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 value

  data_type: 'integer'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "statname",
  { data_type => "varchar", is_nullable => 0, size => 50 },
  "arg",
  { data_type => "varchar", is_nullable => 0, size => 50 },
  "clusterid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "value",
  { data_type => "integer", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</statname>

=item * L</arg>

=item * L</clusterid>

=back

=cut

__PACKAGE__->set_primary_key("statname", "arg", "clusterid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:f2CM29Vpgw7i9JMAtFPPNg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
