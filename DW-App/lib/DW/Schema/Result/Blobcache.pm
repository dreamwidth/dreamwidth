use utf8;
package DW::Schema::Result::Blobcache;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Blobcache

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

=head1 TABLE: C<blobcache>

=cut

__PACKAGE__->table("blobcache");

=head1 ACCESSORS

=head2 bckey

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 dateupdate

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 value

  data_type: 'mediumblob'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "bckey",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "dateupdate",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "value",
  { data_type => "mediumblob", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</bckey>

=back

=cut

__PACKAGE__->set_primary_key("bckey");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ltLXEqBj/X+5yxonjKSeUQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
