use utf8;
package DW::Schema::Result::Media;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Media

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

=head1 TABLE: C<media>

=cut

__PACKAGE__->table("media");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 mediaid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 anum

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 ext

  data_type: 'varchar'
  is_nullable: 0
  size: 10

=head2 state

  data_type: 'char'
  default_value: 'A'
  is_nullable: 0
  size: 1

=head2 mediatype

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 security

  data_type: 'enum'
  default_value: 'public'
  extra: {list => ["public","private","usemask"]}
  is_nullable: 0

=head2 allowmask

  data_type: 'bigint'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 logtime

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 mimetype

  data_type: 'varchar'
  is_nullable: 0
  size: 60

=head2 filesize

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "mediaid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "anum",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "ext",
  { data_type => "varchar", is_nullable => 0, size => 10 },
  "state",
  { data_type => "char", default_value => "A", is_nullable => 0, size => 1 },
  "mediatype",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "security",
  {
    data_type => "enum",
    default_value => "public",
    extra => { list => ["public", "private", "usemask"] },
    is_nullable => 0,
  },
  "allowmask",
  {
    data_type => "bigint",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "logtime",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "mimetype",
  { data_type => "varchar", is_nullable => 0, size => 60 },
  "filesize",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=item * L</mediaid>

=back

=cut

__PACKAGE__->set_primary_key("userid", "mediaid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:yV1cs70Z7QhxJZrRxu3OrA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
