use utf8;
package DW::Schema::Result::ImportItem;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::ImportItem

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

=head1 TABLE: C<import_items>

=cut

__PACKAGE__->table("import_items");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 item

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 status

  data_type: 'enum'
  default_value: 'init'
  extra: {list => ["init","ready","queued","failed","succeeded","aborted"]}
  is_nullable: 0

=head2 created

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 last_touch

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 import_data_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 priority

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "item",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "status",
  {
    data_type => "enum",
    default_value => "init",
    extra => {
      list => ["init", "ready", "queued", "failed", "succeeded", "aborted"],
    },
    is_nullable => 0,
  },
  "created",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "last_touch",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "import_data_id",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "priority",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=item * L</item>

=item * L</import_data_id>

=back

=cut

__PACKAGE__->set_primary_key("userid", "item", "import_data_id");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Dv1T1oiOZE59dADeUPrDlw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
