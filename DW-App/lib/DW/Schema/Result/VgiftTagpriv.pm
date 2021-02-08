use utf8;
package DW::Schema::Result::VgiftTagpriv;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::VgiftTagpriv

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

=head1 TABLE: C<vgift_tagpriv>

=cut

__PACKAGE__->table("vgift_tagpriv");

=head1 ACCESSORS

=head2 tagid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 prlid

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 arg

  data_type: 'varchar'
  is_nullable: 0
  size: 40

=cut

__PACKAGE__->add_columns(
  "tagid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "prlid",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
  "arg",
  { data_type => "varchar", is_nullable => 0, size => 40 },
);

=head1 PRIMARY KEY

=over 4

=item * L</tagid>

=item * L</prlid>

=item * L</arg>

=back

=cut

__PACKAGE__->set_primary_key("tagid", "prlid", "arg");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:IqZDShD2QWH7gLx3C3QWuw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
