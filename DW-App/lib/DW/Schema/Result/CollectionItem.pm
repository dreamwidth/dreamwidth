use utf8;
package DW::Schema::Result::CollectionItem;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::CollectionItem

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

=head1 TABLE: C<collection_items>

=cut

__PACKAGE__->table("collection_items");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 colitemid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 colid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 itemtype

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 itemownerid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 itemid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 logtime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "colitemid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "colid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "itemtype",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "itemownerid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "itemid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "logtime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=item * L</colid>

=item * L</colitemid>

=back

=cut

__PACKAGE__->set_primary_key("userid", "colid", "colitemid");

=head1 UNIQUE CONSTRAINTS

=head2 C<userid>

=over 4

=item * L</userid>

=item * L</colid>

=item * L</itemtype>

=item * L</itemownerid>

=item * L</itemid>

=back

=cut

__PACKAGE__->add_unique_constraint(
  "userid",
  ["userid", "colid", "itemtype", "itemownerid", "itemid"],
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:LJCmNbTYZrSAjZ+ix5ma3w


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
