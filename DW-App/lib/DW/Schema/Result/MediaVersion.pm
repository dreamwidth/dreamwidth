use utf8;
package DW::Schema::Result::MediaVersion;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::MediaVersion

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

=head1 TABLE: C<media_versions>

=cut

__PACKAGE__->table("media_versions");

=head1 ACCESSORS

=head2 userid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 mediaid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 versionid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 width

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 height

  data_type: 'smallint'
  extra: {unsigned => 1}
  is_nullable: 0

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
  "versionid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "width",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
  "height",
  { data_type => "smallint", extra => { unsigned => 1 }, is_nullable => 0 },
  "filesize",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</userid>

=item * L</mediaid>

=item * L</versionid>

=back

=cut

__PACKAGE__->set_primary_key("userid", "mediaid", "versionid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:gtp045mLUCKXxWQXMSLAKg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
