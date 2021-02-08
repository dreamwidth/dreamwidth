use utf8;
package DW::Schema::Result::Code;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Code

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

=head1 TABLE: C<codes>

=cut

__PACKAGE__->table("codes");

=head1 ACCESSORS

=head2 type

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 10

=head2 code

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 7

=head2 item

  data_type: 'varchar'
  is_nullable: 1
  size: 80

=head2 sortorder

  data_type: 'smallint'
  default_value: 0
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "type",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 10 },
  "code",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 7 },
  "item",
  { data_type => "varchar", is_nullable => 1, size => 80 },
  "sortorder",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</type>

=item * L</code>

=back

=cut

__PACKAGE__->set_primary_key("type", "code");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:g3oQ8xctt1Dig62naV1Nug


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
