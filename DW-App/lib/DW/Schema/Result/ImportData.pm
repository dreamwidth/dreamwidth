use utf8;
package DW::Schema::Result::ImportData;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::ImportData

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

=head1 TABLE: C<import_data>

=cut

__PACKAGE__->table("import_data");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 import_data_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 hostname

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 username

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 usejournal

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 password_md5

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 groupmap

  data_type: 'blob'
  is_nullable: 1

=head2 options

  data_type: 'blob'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "import_data_id",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "hostname",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "username",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "usejournal",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "password_md5",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "groupmap",
  { data_type => "blob", is_nullable => 1 },
  "options",
  { data_type => "blob", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=item * L</import_data_id>

=back

=cut

__PACKAGE__->set_primary_key("userid", "import_data_id");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:hr1fkUo+S4XznmZJ+8l7VA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
