use utf8;
package DW::Schema::Result::Noderef;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Noderef

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

=head1 TABLE: C<noderefs>

=cut

__PACKAGE__->table("noderefs");

=head1 ACCESSORS

=head2 nodetype

  data_type: 'char'
  default_value: (empty string)
  is_nullable: 0
  size: 1

=head2 nodeid

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 urlmd5

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 32

=head2 url

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 120

=cut

__PACKAGE__->add_columns(
  "nodetype",
  { data_type => "char", default_value => "", is_nullable => 0, size => 1 },
  "nodeid",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "urlmd5",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 32 },
  "url",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 120 },
);

=head1 PRIMARY KEY

=over 4

=item * L</nodetype>

=item * L</nodeid>

=item * L</urlmd5>

=back

=cut

__PACKAGE__->set_primary_key("nodetype", "nodeid", "urlmd5");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:DWvjY6Y0MVFx6yvzU3mfow


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
