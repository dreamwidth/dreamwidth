use utf8;
package DW::Schema::Result::Pollquestion2;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

DW::Schema::Result::Pollquestion2

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

=head1 TABLE: C<pollquestion2>

=cut

__PACKAGE__->table("pollquestion2");

=head1 ACCESSORS

=head2 journalid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 pollid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 pollqid

  data_type: 'tinyint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 sortorder

  data_type: 'tinyint'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 type

  data_type: 'enum'
  extra: {list => ["check","radio","drop","text","scale"]}
  is_nullable: 0

=head2 opts

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 qtext

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "journalid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "pollid",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "pollqid",
  { data_type => "tinyint", extra => { unsigned => 1 }, is_nullable => 0 },
  "sortorder",
  {
    data_type => "tinyint",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "type",
  {
    data_type => "enum",
    extra => { list => ["check", "radio", "drop", "text", "scale"] },
    is_nullable => 0,
  },
  "opts",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "qtext",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</journalid>

=item * L</pollid>

=item * L</pollqid>

=back

=cut

__PACKAGE__->set_primary_key("journalid", "pollid", "pollqid");


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2021-02-07 23:50:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:7og4NVupIpdC1k8R9sgkAw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
