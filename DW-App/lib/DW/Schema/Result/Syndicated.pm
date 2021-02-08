use utf8;
package DW::Schema::Result::Syndicated;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Syndicated

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

=head1 TABLE: C<syndicated>

=cut

__PACKAGE__->table("syndicated");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 synurl

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 checknext

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  default_value: 'CURRENT_TIMESTAMP'
  is_nullable: 0

=head2 lastcheck

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 lastmod

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 etag

  data_type: 'varchar'
  is_nullable: 1
  size: 80

=head2 fuzzy_token

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 laststatus

  data_type: 'varchar'
  is_nullable: 1
  size: 80

=head2 lastnew

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 oldest_ourdate

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 numreaders

  data_type: 'mediumint'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "synurl",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "checknext",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    default_value => "CURRENT_TIMESTAMP",
    is_nullable => 0,
  },
  "lastcheck",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "lastmod",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "etag",
  { data_type => "varchar", is_nullable => 1, size => 80 },
  "fuzzy_token",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "laststatus",
  { data_type => "varchar", is_nullable => 1, size => 80 },
  "lastnew",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "oldest_ourdate",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "numreaders",
  { data_type => "mediumint", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=back

=cut

__PACKAGE__->set_primary_key("userid");

=head1 UNIQUE CONSTRAINTS

=head2 C<synurl>

=over 4

=item * L</synurl>

=back

=cut

__PACKAGE__->add_unique_constraint("synurl", ["synurl"]);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:oOLiS9bNqgoW0F59o7Qh+w


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
