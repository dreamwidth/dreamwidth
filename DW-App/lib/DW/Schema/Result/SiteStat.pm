use utf8;
package DW::Schema::Result::SiteStat;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::SiteStat

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

=head1 TABLE: C<site_stats>

=cut

__PACKAGE__->table("site_stats");

=head1 ACCESSORS

=head2 category_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 key_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 insert_time

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 value

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "category_id",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "key_id",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "insert_time",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "value",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:/TV+57op/eJJ/hxEpEljpA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
